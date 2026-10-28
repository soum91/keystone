import Foundation
import CryptoKit

/// How to reach the bridge away from home: an MQTT topic on a public broker, end-to-end encrypted with a
/// key the bridge hands out over the LAN. The broker only ever sees AES-GCM ciphertext.
struct RelayConfig: Codable, Equatable {
    var broker: String      // wss://…/mqtt
    var id: String
    var key: String         // 64 hex
    var on: Bool

    static var stored: RelayConfig? {
        get { AppGroup.read(RelayConfig.self, "relay.json") }
        set { if let v = newValue { AppGroup.write(v, "relay.json") } else { AppGroup.remove("relay.json") } }
    }

    var symmetricKey: SymmetricKey? {
        var bytes = [UInt8]()
        var i = key.startIndex
        while i < key.endIndex, let j = key.index(i, offsetBy: 2, limitedBy: key.endIndex) {
            guard let b = UInt8(key[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        return bytes.count == 32 ? SymmetricKey(data: bytes) : nil
    }
}

enum RelayError: LocalizedError {
    case notSetUp, timeout, broker(String)
    var errorDescription: String? {
        switch self {
        case .notSetUp: return "Remote access isn't set up yet. Open Keystone once on your home Wi-Fi."
        case .timeout: return "The bridge didn't answer through the relay. It may be offline or remote access is off."
        case .broker(let m): return "Relay: \(m)"
        }
    }
}

/// Minimal MQTT 3.1.1 over WebSocket (QoS 0 only), enough to publish requests and receive answers.
actor RelayClient {
    static let shared = RelayClient()

    private var ws: URLSessionWebSocketTask?
    private var session: URLSession?
    private var buffer = Data()
    private var ready = false
    private var connecting: Task<Void, Error>?
    private var waiting: [String: CheckedContinuation<(Int, Data), Error>] = [:]
    private var connack: CheckedContinuation<Void, Error>?
    private var cfg: RelayConfig?
    private var pinger: Task<Void, Never>?

    // MARK: Public

    func request(_ method: String, _ path: String, headers: [String: String], body: String?, timeout: Double) async throws -> (Int, Data) {
        guard let c = RelayConfig.stored, c.on, let key = c.symmetricKey else { throw RelayError.notSetUp }
        try await ensureConnected(c)
        let rid = UUID().uuidString
        var msg: [String: Any] = ["i": rid, "t": Int(Date().timeIntervalSince1970), "m": method, "p": path, "h": headers]
        if let body { msg["b"] = body }
        let plain = try JSONSerialization.data(withJSONObject: msg)
        let sealed = try AES.GCM.seal(plain, using: key).combined!.base64EncodedData()
        try await send(Self.publish(topic: "keystone/\(c.id)/req", payload: sealed))
        return try await withCheckedThrowingContinuation { cont in
            waiting[rid] = cont
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self.fail(rid, RelayError.timeout)
            }
        }
    }

    func disconnect() {
        pinger?.cancel()
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        ready = false
    }

    // MARK: Connection

    private func ensureConnected(_ c: RelayConfig) async throws {
        if ready, cfg == c, ws != nil { return }
        if let t = connecting { return try await t.value }
        let t = Task { try await self.connect(c) }
        connecting = t
        defer { connecting = nil }
        try await t.value
    }

    private func connect(_ c: RelayConfig) async throws {
        disconnect()
        cfg = c
        guard let url = URL(string: c.broker) else { throw RelayError.broker("bad broker address") }
        let s = URLSession(configuration: .default)
        session = s
        let task = s.webSocketTask(with: url, protocols: ["mqtt"])
        ws = task
        task.resume()
        receiveLoop(task)
        try await send(Self.connectPacket(clientID: "ks-app-\(UUID().uuidString.prefix(12))"))
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connack = cont
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await self.failConnack(RelayError.broker("no answer from the broker"))
            }
        }
        try await send(Self.subscribe(topic: "keystone/\(c.id)/res", packetID: 1))
        ready = true
        pinger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                try? await self?.send(Data([0xC0, 0x00]))
            }
        }
    }

    private func failConnack(_ e: Error) {
        connack?.resume(throwing: e)
        connack = nil
    }

    private func fail(_ rid: String, _ e: Error) {
        waiting.removeValue(forKey: rid)?.resume(throwing: e)
    }

    private func send(_ d: Data) async throws {
        guard let ws else { throw RelayError.broker("not connected") }
        try await ws.send(.data(d))
    }

    private nonisolated func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let m):
                let d: Data
                switch m {
                case .data(let x): d = x
                case .string(let s): d = Data(s.utf8)
                @unknown default: d = Data()
                }
                Task { await self.ingest(d) }
                self.receiveLoop(task)
            case .failure(let e):
                Task { await self.dropped(e) }
            }
        }
    }

    private func dropped(_ e: Error) {
        ready = false
        ws = nil
        failConnack(e)
        for (k, c) in waiting { c.resume(throwing: RelayError.broker(e.localizedDescription)); waiting[k] = nil }
    }

    private func ingest(_ d: Data) {
        buffer.append(d)
        while let pkt = Self.nextPacket(buffer) {
            let (type, body, used) = pkt
            buffer.removeFirst(used)
            switch type >> 4 {
            case 2:   // CONNACK
                if body.count >= 2, body[body.startIndex + 1] == 0 { connack?.resume() } else { connack?.resume(throwing: RelayError.broker("refused")) }
                connack = nil
            case 3:   // PUBLISH
                handlePublish(type, body)
            default:
                break
            }
        }
    }

    private func handlePublish(_ type: UInt8, _ body: Data) {
        let b = [UInt8](body)
        guard b.count > 2 else { return }
        let tlen = Int(b[0]) << 8 | Int(b[1])
        var p = 2 + tlen
        if (type >> 1) & 3 > 0 { p += 2 }
        guard p <= b.count, let key = cfg?.symmetricKey,
              let raw = Data(base64Encoded: Data(b[p...])),
              let box = try? AES.GCM.SealedBox(combined: raw),
              let plain = try? AES.GCM.open(box, using: key),
              let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let rid = obj["i"] as? String else { return }
        let code = (obj["c"] as? Int) ?? 0
        let bodyData = Data(((obj["b"] as? String) ?? "").utf8)
        waiting.removeValue(forKey: rid)?.resume(returning: (code, bodyData))
    }

    // MARK: MQTT packets

    private static func remaining(_ n: Int) -> Data {
        var x = n
        var out = Data()
        repeat {
            var byte = UInt8(x % 128)
            x /= 128
            if x > 0 { byte |= 0x80 }
            out.append(byte)
        } while x > 0
        return out
    }

    private static func str(_ s: String) -> Data {
        let u = Data(s.utf8)
        return Data([UInt8(u.count >> 8), UInt8(u.count & 0xff)]) + u
    }

    static func connectPacket(clientID: String) -> Data {
        var v = str("MQTT")
        v.append(contentsOf: [0x04, 0x02, 0x00, 60])   // level 4, clean session, keepalive 60 s
        v.append(str(clientID))
        return Data([0x10]) + remaining(v.count) + v
    }

    static func subscribe(topic: String, packetID: UInt16) -> Data {
        var v = Data([UInt8(packetID >> 8), UInt8(packetID & 0xff)])
        v.append(str(topic))
        v.append(0x00)
        return Data([0x82]) + remaining(v.count) + v
    }

    static func publish(topic: String, payload: Data) -> Data {
        let v = str(topic) + payload
        return Data([0x30]) + remaining(v.count) + v
    }

    /// (first byte, body, bytes used), or nil if the buffer doesn't hold a whole packet yet.
    static func nextPacket(_ d: Data) -> (UInt8, Data, Int)? {
        let b = [UInt8](d)
        guard b.count >= 2 else { return nil }
        var mult = 1, len = 0, i = 1
        while true {
            guard i < b.count, i <= 4 else { return nil }
            len += Int(b[i] & 0x7f) * mult
            mult *= 128
            if b[i] & 0x80 == 0 { break }
            i += 1
        }
        let start = i + 1
        guard b.count >= start + len else { return nil }
        return (b[0], Data(b[start..<(start + len)]), start + len)
    }
}

/// LAN first; the relay when the bridge isn't reachable directly (away from home, VPN on).
enum Transport {
    private static var preferRelayUntil = Date.distantPast
    private static let lock = NSLock()
    static var lastWasRelay = false

    static func send(_ link: BridgeLink, method: String, path: String, headers: [String: String] = [:],
                     body: Data? = nil, timeout: Double = 6) async throws -> (Int, Data) {
        let relayReady = RelayConfig.stored?.on == true
        lock.lock(); let skipLAN = relayReady && preferRelayUntil > Date(); lock.unlock()
        if !skipLAN {
            do {
                let r = try await lan(link, method, path, headers, body, relayReady ? min(timeout, 2.5) : timeout)
                lastWasRelay = false
                return r
            } catch let e as URLError where relayReady && [.timedOut, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost].contains(e.code) {
                lock.lock(); preferRelayUntil = Date().addingTimeInterval(45); lock.unlock()
            }
        }
        let r = try await RelayClient.shared.request(method, path, headers: headers,
                                                     body: body.map { String(decoding: $0, as: UTF8.self) }, timeout: max(timeout, 10))
        lastWasRelay = true
        return r
    }

    private static func lan(_ link: BridgeLink, _ method: String, _ path: String, _ headers: [String: String],
                            _ body: Data?, _ timeout: Double) async throws -> (Int, Data) {
        guard let u = BridgeAPI.url(link.host, link.port, path) else { throw BridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.httpMethod = method
        req.timeoutInterval = timeout
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}
