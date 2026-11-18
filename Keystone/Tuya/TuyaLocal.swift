import Foundation
import Network
import CryptoKit
import CommonCrypto

/// Copied from Afterglow (Shared/TuyaLocal.swift). Tuya's LAN protocol (3.3, 3.4 and 3.5), ported from tinytuya. Talking to the device directly
/// exposes every raw data point, including the ones Tuya's cloud API hides (fan speed, display).

struct LocalError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

struct TuyaFrame {
    let seq: UInt32
    let cmd: UInt32
    let payload: [UInt8]

    var json: [String: Any]? {
        guard let start = payload.firstIndex(of: UInt8(ascii: "{")) else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(payload[start...])) as? [String: Any]
    }

    var dps: [String: JSONValue]? {
        guard let j = json else { return nil }
        let raw = (j["dps"] as? [String: Any]) ?? ((j["data"] as? [String: Any])?["dps"] as? [String: Any])
        guard let raw else { return nil }
        var out: [String: JSONValue] = [:]
        for (k, v) in raw { out[k] = JSONValue.from(v) }
        return out
    }

    var text: String { String(decoding: payload, as: UTF8.self) }
}

enum TuyaCmd {
    static let sessStart: UInt32 = 0x03, sessResp: UInt32 = 0x04, sessFinish: UInt32 = 0x05
    static let control: UInt32 = 0x07, status: UInt32 = 0x08, heartbeat: UInt32 = 0x09
    static let dpQuery: UInt32 = 0x0a, controlNew: UInt32 = 0x0d, dpQueryNew: UInt32 = 0x10
    static let noHeader: Set<UInt32> = [0x0a, 0x10, 0x12, 0x09, 0x03, 0x04, 0x05, 0x40]
}

// MARK: - Bytes and crypto

extension Array where Element == UInt8 {
    mutating func appendBE(_ v: UInt32) {
        append(UInt8((v >> 24) & 0xff)); append(UInt8((v >> 16) & 0xff))
        append(UInt8((v >> 8) & 0xff)); append(UInt8(v & 0xff))
    }

    func be32(_ i: Int) -> UInt32 {
        UInt32(self[i]) << 24 | UInt32(self[i + 1]) << 16 | UInt32(self[i + 2]) << 8 | UInt32(self[i + 3])
    }

    func hasPrefixBytes(_ p: [UInt8]) -> Bool { count >= p.count && Array(self[0..<p.count]) == p }
}

enum LocalCrypto {
    static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xffffffff
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffffffff
    }

    static func hmac(_ data: [UInt8], key: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: data, using: SymmetricKey(data: key)))
    }

    static func ecbEncrypt(_ data: [UInt8], key: [UInt8], pad: Bool = true) -> [UInt8] {
        var input = data
        if pad {
            let n = 16 - input.count % 16
            input += [UInt8](repeating: UInt8(n), count: n)
        }
        return ecb(CCOperation(kCCEncrypt), input, key)
    }

    static func ecbDecrypt(_ data: [UInt8], key: [UInt8]) -> [UInt8]? {
        guard !data.isEmpty, data.count % 16 == 0 else { return nil }
        var out = ecb(CCOperation(kCCDecrypt), data, key)
        if let last = out.last, last >= 1, last <= 16, Int(last) <= out.count { out.removeLast(Int(last)) }
        return out
    }

    private static func ecb(_ op: CCOperation, _ input: [UInt8], _ key: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: input.count + 16)
        let cap = out.count
        var moved = 0
        let status = CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                             key, key.count, nil, input, input.count, &out, cap, &moved)
        return status == kCCSuccess ? Array(out.prefix(moved)) : []
    }

    static func gcmSeal(_ plain: [UInt8], key: [UInt8], iv: [UInt8], aad: [UInt8]) throws -> (ct: [UInt8], tag: [UInt8]) {
        let box = try AES.GCM.seal(plain, using: SymmetricKey(data: key), nonce: AES.GCM.Nonce(data: iv), authenticating: aad)
        return (Array(box.ciphertext), Array(box.tag))
    }

    static func gcmOpen(_ ct: [UInt8], tag: [UInt8], key: [UInt8], iv: [UInt8], aad: [UInt8]) throws -> [UInt8] {
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: iv), ciphertext: ct, tag: tag)
        return Array(try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: aad))
    }

    static func random(_ n: Int) -> [UInt8] { (0..<n).map { _ in UInt8.random(in: 0...255) } }
}

// MARK: - Framing

final class TuyaCodec {
    let version: Double
    let realKey: [UInt8]
    var key: [UInt8]
    var seq: UInt32 = 1

    init(version: Double, localKey: String) {
        self.version = version
        realKey = Array(localKey.utf8)
        key = realKey
    }

    private var versionTag: [UInt8] { Array(String(format: "%.1f", version).utf8) }
    private var versionHeader: [UInt8] { versionTag + [UInt8](repeating: 0, count: 12) }

    func encode(cmd: UInt32, payload raw: [UInt8]) throws -> [UInt8] {
        defer { seq &+= 1 }
        let header3x = TuyaCmd.noHeader.contains(cmd) ? [] : versionHeader
        if version >= 3.5 {
            let p = header3x + raw
            var header: [UInt8] = []
            header.appendBE(0x00006699)
            header += [0, 0]
            header.appendBE(seq); header.appendBE(cmd); header.appendBE(UInt32(p.count + 12 + 16))
            let iv = LocalCrypto.random(12)
            let sealed = try LocalCrypto.gcmSeal(p, key: key, iv: iv, aad: Array(header[4...]))
            return header + iv + sealed.ct + sealed.tag + [0, 0, 0x99, 0x66]
        }
        if version >= 3.4 {
            let enc = LocalCrypto.ecbEncrypt(header3x + raw, key: key)
            var header: [UInt8] = []
            header.appendBE(0x000055AA); header.appendBE(seq); header.appendBE(cmd); header.appendBE(UInt32(enc.count + 36))
            return header + enc + LocalCrypto.hmac(header + enc, key: key) + [0, 0, 0xAA, 0x55]
        }
        let body = header3x + LocalCrypto.ecbEncrypt(raw, key: key)
        var out: [UInt8] = []
        out.appendBE(0x000055AA); out.appendBE(seq); out.appendBE(cmd); out.appendBE(UInt32(body.count + 8))
        out += body
        out.appendBE(LocalCrypto.crc32(out))
        out += [0, 0, 0xAA, 0x55]
        return out
    }

    /// Takes complete frames off the front of the buffer; leaves any partial frame for next time.
    func decode(_ buffer: inout [UInt8]) -> [TuyaFrame] {
        var frames: [TuyaFrame] = []
        while true {
            while buffer.count >= 4, buffer.be32(0) != 0x000055AA, buffer.be32(0) != 0x00006699 {
                buffer.removeFirst()
            }
            guard buffer.count >= 4 else { break }
            if buffer.be32(0) == 0x000055AA {
                guard buffer.count >= 16 else { break }
                let len = Int(buffer.be32(12))
                if len > 65536 { buffer.removeFirst(4); continue }
                let total = 16 + len
                guard buffer.count >= total else { break }
                let frame = Array(buffer[0..<total])
                buffer.removeFirst(total)
                let endLen = version >= 3.4 ? 36 : 8
                guard total >= 16 + endLen else { continue }
                var body = Array(frame[16..<(total - endLen)])
                if body.count >= 4, body[0] == 0, body[1] == 0, body[2] == 0,
                   version < 3.4 || body.count % 16 == 4 {
                    body.removeFirst(4)   // return code
                }
                frames.append(TuyaFrame(seq: frame.be32(4), cmd: frame.be32(8), payload: decrypt55AA(body)))
            } else {
                guard buffer.count >= 18 else { break }
                let len = Int(buffer.be32(14))
                if len > 65536 { buffer.removeFirst(4); continue }
                let total = 18 + len + 4
                guard buffer.count >= total else { break }
                let frame = Array(buffer[0..<total])
                buffer.removeFirst(total)
                guard total >= 18 + 12 + 16 + 4 else { continue }
                let iv = Array(frame[18..<30])
                let tag = Array(frame[(total - 20)..<(total - 4)])
                let ct = Array(frame[30..<(total - 20)])
                guard var plain = try? LocalCrypto.gcmOpen(ct, tag: tag, key: key, iv: iv, aad: Array(frame[4..<18])) else { continue }
                if plain.count >= 4 { plain.removeFirst(4) }   // return code
                if plain.hasPrefixBytes(versionTag) { plain.removeFirst(min(15, plain.count)) }
                frames.append(TuyaFrame(seq: frame.be32(6), cmd: frame.be32(10), payload: plain))
            }
        }
        return frames
    }

    private func decrypt55AA(_ body: [UInt8]) -> [UInt8] {
        var b = body
        if version >= 3.4 {
            guard var plain = LocalCrypto.ecbDecrypt(b, key: key) else { return b }
            if plain.hasPrefixBytes(versionTag) { plain.removeFirst(min(15, plain.count)) }
            return plain
        }
        if b.hasPrefixBytes(versionTag) { b.removeFirst(min(15, b.count)) }
        if b.first == UInt8(ascii: "{") { return b }
        return LocalCrypto.ecbDecrypt(b, key: key) ?? b
    }
}

// MARK: - Connection

// OnceFlag lives in Keystone/App/Finder.swift.

actor LocalLink {
    let devId: String
    let host: String
    let localKey: String
    let version: Double
    private let knownDPs: [String]
    /// Seconds to wait for each reply. Short when probing which device is which.
    private let replyTimeout: Double
    private let onDPS: @Sendable ([String: JSONValue]) -> Void
    private let onClose: @Sendable (String) -> Void

    private var conn: NWConnection?
    private var codec: TuyaCodec
    private var buffer: [UInt8] = []
    private var inbox: [TuyaFrame] = []
    private var heartbeat: Task<Void, Never>?
    private var device22 = false
    private(set) var isOpen = false

    init(devId: String, host: String, localKey: String, version: Double, knownDPs: [String] = [], timeout: Double = 4,
         onDPS: @escaping @Sendable ([String: JSONValue]) -> Void = { _ in },
         onClose: @escaping @Sendable (String) -> Void = { _ in }) {
        self.devId = devId
        self.host = host
        self.localKey = localKey
        self.version = version
        self.knownDPs = knownDPs
        self.replyTimeout = timeout
        self.onDPS = onDPS
        self.onClose = onClose
        codec = TuyaCodec(version: version, localKey: localKey)
    }

    // MARK: Public

    func open() async throws {
        let c = NWConnection(host: NWEndpoint.Host(host), port: 6668, using: .tcp)
        conn = c
        try await Self.waitReady(c, timeout: min(replyTimeout, 4))
        isOpen = true
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                Task { await self?.closed("Connection dropped") }
            default: break
            }
        }
        receive(c)
        if version >= 3.4 { try await negotiate() }
        startHeartbeat()
    }

    func close() {
        heartbeat?.cancel()
        heartbeat = nil
        conn?.cancel()
        conn = nil
        isOpen = false
    }

    func query() async throws -> [String: JSONValue] {
        inbox.removeAll()
        if version >= 3.4 {
            try await send(TuyaCmd.dpQueryNew, json: [:])
            return try await waitDPS([TuyaCmd.dpQueryNew, TuyaCmd.dpQuery, TuyaCmd.status], timeout: replyTimeout)
        }
        let t = String(Int(Date().timeIntervalSince1970))
        if device22 {
            var dps: [String: Any] = [:]
            for k in (knownDPs.isEmpty ? ["1"] : knownDPs) { dps[k] = NSNull() }
            try await send(TuyaCmd.controlNew, json: ["devId": devId, "uid": devId, "t": t, "dps": dps])
            return try await waitDPS([TuyaCmd.controlNew, TuyaCmd.dpQuery, TuyaCmd.status], timeout: replyTimeout)
        }
        try await send(TuyaCmd.dpQuery, json: ["gwId": devId, "devId": devId, "uid": devId, "t": t])
        let frame = try await wait([TuyaCmd.dpQuery], timeout: replyTimeout)
        if frame.text.contains("data unvalid") {
            device22 = true
            return try await query()
        }
        if let dps = frame.dps { return dps }
        // Some devices answer with no data points at all until a command has been sent.
        if frame.json != nil { return [:] }
        throw LocalError("Unexpected reply from the device.")
    }

    /// 3.4+ already proved the key in the handshake, so a silent status query is fine there.
    func statusAfterOpen() async throws -> [String: JSONValue] {
        if version >= 3.4 { return (try? await query()) ?? [:] }
        return try await query()
    }

    func set(_ dps: [String: JSONValue]) async throws {
        var d: [String: Any] = [:]
        for (k, v) in dps { d[k] = v.any }
        if version >= 3.4 {
            try await send(TuyaCmd.controlNew, json: ["protocol": 5, "t": Int(Date().timeIntervalSince1970), "data": ["dps": d]])
        } else {
            try await send(TuyaCmd.control, json: ["devId": devId, "uid": devId, "t": String(Int(Date().timeIntervalSince1970)), "dps": d])
        }
    }

    /// Sends and waits briefly for the device to echo the new state. Nil if it stayed quiet
    /// (some firmwares only report on the next query), which is not treated as a failure.
    func setConfirmed(_ dps: [String: JSONValue], timeout: Double = 1.2) async throws -> [String: JSONValue]? {
        inbox.removeAll()
        try await set(dps)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let i = inbox.firstIndex(where: { [TuyaCmd.status, TuyaCmd.control, TuyaCmd.controlNew].contains($0.cmd) && $0.dps != nil }) {
                return inbox.remove(at: i).dps
            }
            guard isOpen else { throw LocalError("Connection closed.") }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        return nil
    }

    // MARK: Session key (3.4 / 3.5)

    private func negotiate() async throws {
        let localNonce = LocalCrypto.random(16)
        codec.key = codec.realKey
        try await sendRaw(try codec.encode(cmd: TuyaCmd.sessStart, payload: localNonce))
        let resp = try await wait([TuyaCmd.sessResp], timeout: min(replyTimeout, 3))
        guard resp.payload.count >= 48 else { throw LocalError("Handshake failed (short reply).") }
        let remote = Array(resp.payload[0..<16])
        guard LocalCrypto.hmac(localNonce, key: codec.realKey) == Array(resp.payload[16..<48]) else {
            throw LocalError("Handshake failed: wrong local key or protocol version.")
        }
        try await sendRaw(try codec.encode(cmd: TuyaCmd.sessFinish, payload: LocalCrypto.hmac(remote, key: codec.realKey)))
        let mixed = zip(localNonce, remote).map { $0 ^ $1 }
        if version >= 3.5 {
            codec.key = try LocalCrypto.gcmSeal(mixed, key: codec.realKey, iv: Array(localNonce[0..<12]), aad: []).ct
        } else {
            codec.key = LocalCrypto.ecbEncrypt(mixed, key: codec.realKey, pad: false)
        }
    }

    // MARK: Plumbing

    private func send(_ cmd: UInt32, json: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        try await sendRaw(try codec.encode(cmd: cmd, payload: Array(data)))
    }

    private func sendRaw(_ bytes: [UInt8]) async throws {
        guard let c = conn else { throw LocalError("Not connected.") }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            c.send(content: Data(bytes), completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            })
        }
    }

    private nonisolated func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, done, err in
            guard let self else { return }
            let bytes = data.map { [UInt8]($0) } ?? []
            let ended = done || err != nil
            Task { await self.ingest(bytes, ended: ended, conn: c) }
        }
    }

    private func ingest(_ bytes: [UInt8], ended: Bool, conn c: NWConnection) {
        buffer += bytes
        for f in codec.decode(&buffer) {
            if let dps = f.dps, !dps.isEmpty { onDPS(dps) }
            inbox.append(f)
            if inbox.count > 50 { inbox.removeFirst(inbox.count - 50) }
        }
        if ended {
            closed("The light closed the connection")
        } else if c === conn {
            receive(c)
        }
    }

    private func closed(_ why: String) {
        guard isOpen else { return }
        close()
        onClose(why)
    }

    private func wait(_ cmds: Set<UInt32>, timeout: Double) async throws -> TuyaFrame {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let i = inbox.firstIndex(where: { cmds.contains($0.cmd) }) {
                return inbox.remove(at: i)
            }
            guard isOpen else { throw LocalError("Connection closed.") }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        throw LocalError("No reply from the device.")
    }

    private func waitDPS(_ cmds: Set<UInt32>, timeout: Double) async throws -> [String: JSONValue] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let left = deadline.timeIntervalSinceNow
            let f = try await wait(cmds, timeout: max(left, 0.05))
            if let dps = f.dps { return dps }
            if f.json != nil { return [:] }
        }
        throw LocalError("No status from the device.")
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self else { return }
                try? await self.beat()
            }
        }
    }

    private func beat() async throws {
        guard isOpen else { return }
        try await send(TuyaCmd.heartbeat, json: ["gwId": devId, "devId": devId])
    }

    static func waitReady(_ c: NWConnection, timeout: Double) async throws {
        let once = OnceFlag()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.fire() { cont.resume() }
                case .failed(let e), .waiting(let e):
                    if once.fire() { c.cancel(); cont.resume(throwing: e) }
                case .cancelled:
                    if once.fire() { cont.resume(throwing: LocalError("Connection cancelled.")) }
                default: break
                }
            }
            c.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.fire() { c.cancel(); cont.resume(throwing: LocalError("No answer on port 6668.")) }
            }
        }
    }

    /// Tries each protocol version and returns an open link plus the first status it read.
    static func detect(devId: String, host: String, localKey: String, knownDPs: [String], timeout: Double = 4,
                       versions: [Double] = [3.3, 3.4, 3.5],
                       onDPS: @escaping @Sendable ([String: JSONValue]) -> Void,
                       onClose: @escaping @Sendable (String) -> Void) async throws -> (LocalLink, [String: JSONValue]) {
        var lastError: Error = LocalError("Couldn't talk to the device.")
        for v in versions {
            let link = LocalLink(devId: devId, host: host, localKey: localKey, version: v, knownDPs: knownDPs, timeout: timeout, onDPS: onDPS, onClose: onClose)
            do {
                try await link.open()
                // An empty answer still proves the key works: Some devices report nothing until used.
                return (link, try await link.statusAfterOpen())
            } catch {
                lastError = error
            }
            await link.close()
        }
        throw lastError
    }
}

// MARK: - Finding it on Wi-Fi

enum LocalScan {
    /// This phone's Wi-Fi IPv4 address.
    static func wifiAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: ifa.ifa_name) == "en0" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            ptr = ifa.ifa_next
        }
        return nil
    }

    /// Hosts on this /24 with Tuya's local port open.
    static func openHosts(progress: @escaping @Sendable (Int) -> Void) async -> [String] {
        guard let me = wifiAddress() else { return [] }
        let parts = me.split(separator: ".")
        guard parts.count == 4 else { return [] }
        let base = parts[0..<3].joined(separator: ".")
        let candidates = (1...254).map { "\(base).\($0)" }.filter { $0 != me }
        var found: [String] = []
        var done = 0
        for chunk in stride(from: 0, to: candidates.count, by: 48).map({ Array(candidates[$0..<min($0 + 48, candidates.count)]) }) {
            await withTaskGroup(of: String?.self) { group in
                for host in chunk {
                    group.addTask {
                        let c = NWConnection(host: NWEndpoint.Host(host), port: 6668, using: .tcp)
                        do {
                            try await LocalLink.waitReady(c, timeout: 1.5)
                            c.cancel()
                            return host
                        } catch {
                            c.cancel()
                            return nil
                        }
                    }
                }
                for await h in group {
                    if let h { found.append(h) }
                }
            }
            done += chunk.count
            progress(done)
        }
        return found
    }
}
