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

/// Two free public brokers. The bridge sits on one at a time (it switches when one fails); the phone asks
/// through both at once and takes the first answer, so either broker being down or blocked is survivable.
final class RelayClient: @unchecked Sendable {
    static let shared = RelayClient()
    let links = [RelayLink(broker: "wss://broker.emqx.io:8084/mqtt", label: "EMQX"),
                 RelayLink(broker: "wss://broker.hivemq.com:8884/mqtt", label: "HiveMQ")]

    func disconnect() async { for l in links { await l.disconnect() } }

    func request(_ method: String, _ path: String, headers: [String: String], body: String?, timeout: Double) async throws -> (Int, Data) {
        let race = Race(count: links.count)
        return try await withCheckedThrowingContinuation { cont in
            race.start(cont)
            for l in links {
                Task {
                    do { race.win(try await l.request(method, path, headers: headers, body: body, timeout: timeout)) }
                    catch { race.lose(l.label, error) }
                }
            }
        }
    }

    /// First answer wins; if every broker fails, one error naming what each one said.
    private final class Race: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<(Int, Data), Error>?
        private var left: Int
        private var errors: [(String, Error)] = []
        init(count: Int) { left = count }
        func start(_ c: CheckedContinuation<(Int, Data), Error>) { lock.lock(); cont = c; lock.unlock() }
        func win(_ v: (Int, Data)) {
            lock.lock(); let c = cont; cont = nil; lock.unlock()
            c?.resume(returning: v)
        }
        func lose(_ label: String, _ e: Error) {
            lock.lock()
            errors.append((label, e)); left -= 1
            let done = left == 0 ? cont : nil
            if done != nil { cont = nil }
            let all = errors
            lock.unlock()
            NetLog.add("relay \(label): \(e.localizedDescription)")
            guard let done else { return }
            if all.allSatisfy({ if case RelayError.timeout = $0.1 { return true }; return false }) {
                done.resume(throwing: RelayError.timeout)
            } else {
                done.resume(throwing: RelayError.broker(all.map { "\($0.0): \($0.1.localizedDescription.replacingOccurrences(of: "Relay: ", with: ""))" }.joined(separator: "; ")))
            }
        }
    }
}

/// Minimal MQTT 3.1.1 over WebSocket (QoS 0 only) to one broker, enough to publish requests and receive answers.
actor RelayLink {
    let broker: String
    nonisolated let label: String
    init(broker: String, label: String) { self.broker = broker; self.label = label }

    private var ws: URLSessionWebSocketTask?
    private var session: URLSession?
    private var buffer = Data()
    private var ready = false
    private var connecting: Task<Void, Error>?
    private var waiting: [String: CheckedContinuation<(Int, Data), Error>] = [:]
    private var connack: CheckedContinuation<Void, Error>?
    private var suback: CheckedContinuation<Void, Error>?
    private var cfg: RelayConfig?
    private var pinger: Task<Void, Never>?

    // MARK: Public

    func request(_ method: String, _ path: String, headers: [String: String], body: String?, timeout: Double) async throws -> (Int, Data) {
        guard let c = RelayConfig.stored, c.on, let key = c.symmetricKey else { throw RelayError.notSetUp }
        let reused = ready && cfg == c && ws != nil
        do {
            return try await attempt(c, key, method, path, headers, body, reused ? min(timeout, 6) : timeout)
        } catch {
            guard reused else { throw error }
            // The kept-open connection may be dead (network change, app suspended): start fresh, once.
            disconnect()
            return try await attempt(c, key, method, path, headers, body, timeout)
        }
    }

    private func attempt(_ c: RelayConfig, _ key: SymmetricKey, _ method: String, _ path: String,
                         _ headers: [String: String], _ body: String?, _ timeout: Double) async throws -> (Int, Data) {
        try await ensureConnected(c)
        let rid = UUID().uuidString
        var msg: [String: Any] = ["i": rid, "t": Int(Date().timeIntervalSince1970), "m": method, "p": path, "h": headers]
        if let body { msg["b"] = body }
        let plain = try JSONSerialization.data(withJSONObject: msg)
        let sealed = try AES.GCM.seal(plain, using: key).combined!.base64EncodedData()
        // Register the waiter before sending: a fast reply must not be lost.
        let packet = Self.publish(topic: "keystone/\(c.id)/req", payload: sealed)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Int, Data), Error>) in
            waiting[rid] = cont
            Task {
                do { try await self.send(packet) }
                catch { await self.fail(rid, error); return }
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await self.fail(rid, RelayError.timeout)
            }
        }
    }

    func disconnect() {
        pinger?.cancel()
        pinger = nil
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
        ready = false
        // MQTT frames belong to one TCP/WebSocket session; a partial frame
        // must never be carried into the next broker connection.
        buffer.removeAll(keepingCapacity: true)
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
        guard let url = URL(string: broker) else { throw RelayError.broker("bad broker address") }
        let s = URLSession(configuration: .default)
        session = s
        let task = s.webSocketTask(with: url, protocols: ["mqtt"])
        ws = task
        task.resume()
        receiveLoop(task)
        // Wait for CONNACK, registered before CONNECT goes out so a fast answer can't be missed.
        let hello = Self.connectPacket(clientID: "ks-app-\(UUID().uuidString.prefix(12))")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connack = cont
            Task {
                do { try await self.send(hello) } catch { await self.failConnack(error) }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                await self.failConnack(RelayError.broker("no answer from the broker"))
            }
        }
        // Wait for SUBACK: a request sent before the subscription is live can have its answer dropped.
        let sub = Self.subscribe(topic: "keystone/\(c.id)/res", packetID: 1)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            suback = cont
            Task {
                do { try await self.send(sub) } catch { await self.failSuback(error) }
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                await self.failSuback(RelayError.broker("the broker didn't confirm the answer channel"))
            }
        }
        NetLog.add("relay \(label): connected and listening")
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

    private func failSuback(_ e: Error) {
        suback?.resume(throwing: e)
        suback = nil
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
                Task { await self.ingest(d, from: task) }
                self.receiveLoop(task)
            case .failure(let e):
                Task { await self.dropped(e, task) }
            }
        }
    }

    private func dropped(_ e: Error, _ task: URLSessionWebSocketTask) {
        // Only the current socket counts: replacing a connection cancels the old one, and its last
        // "socket is not connected" must not kill the new connection or the request waiting on it.
        guard task === ws else { return }
        ready = false
        ws = nil
        failConnack(e)
        failSuback(e)
        for (k, c) in waiting { c.resume(throwing: RelayError.broker(e.localizedDescription)); waiting[k] = nil }
    }

    private func ingest(_ d: Data, from task: URLSessionWebSocketTask) {
        // Old sockets can deliver a final receive callback AFTER reconnect.
        // Never parse those bytes with the new broker's configuration/key.
        guard task === ws else { return }
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
            case 9:   // SUBACK (0x80 = refused)
                if body.count >= 3, body[body.startIndex + 2] == 0x80 { suback?.resume(throwing: RelayError.broker("the broker refused the answer channel")) }
                else { suback?.resume() }
                suback = nil
            default:
                break
            }
        }
    }

    private func handlePublish(_ type: UInt8, _ body: Data) {
        let b = [UInt8](body)
        guard b.count > 2 else { return }
        let tlen = Int(b[0]) << 8 | Int(b[1])
        guard 2 + tlen <= b.count,
              let topic = String(bytes: b[2..<(2 + tlen)], encoding: .utf8),
              topic == "keystone/\(cfg?.id ?? "")/res" else { return }
        var p = 2 + tlen
        if (type >> 1) & 3 > 0 { p += 2 }
        guard p <= b.count else { return }
        let cipher = Data(b[p...])
        // A zero-payload MQTT PUBLISH is just the 29-byte response topic plus
        // its two-byte length: 31 bytes. It isn't evidence of a wrong AES key.
        if cipher.isEmpty {
            NetLog.add("relay \(label): ignored empty MQTT response (31-byte topic frame)")
            return
        }
        guard let key = cfg?.symmetricKey,
              let raw = Data(base64Encoded: cipher),
              raw.count >= 29,
              let box = try? AES.GCM.SealedBox(combined: raw),
              let plain = try? AES.GCM.open(box, using: key),
              let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let rid = obj["i"] as? String else {
            NetLog.add("relay \(label): discarded unreadable non-empty response (possible stale key or malformed payload)")
            return
        }
        let code = (obj["c"] as? Int) ?? 0
        let bodyData = Data(((obj["b"] as? String) ?? "").utf8)
        if let w = waiting.removeValue(forKey: rid) { w.resume(returning: (code, bodyData)) }
        else { NetLog.add("relay: answer \(rid.prefix(8)) arrived after the phone gave up") }
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

    private static var nextID: UInt16 = 1
    /// QoS 1: the broker holds it for the bridge's persistent session if the bridge is reconnecting.
    static func publish(topic: String, payload: Data) -> Data {
        nextID = nextID &+ 1; if nextID == 0 { nextID = 1 }
        let v = str(topic) + Data([UInt8(nextID >> 8), UInt8(nextID & 0xff)]) + payload
        return Data([0x32]) + remaining(v.count) + v
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
/// What happened on each try, newest last. Shown in Bridge › Diagnostics and shareable.
enum NetLog {
    private static let lock = NSLock()
    private(set) static var lines: [String] = []
    static func add(_ s: String) {
        let t = Date().formatted(date: .omitted, time: .standard)
        lock.lock(); lines.append("\(t) \(s)"); if lines.count > 200 { lines.removeFirst(lines.count - 200) }; lock.unlock()
    }
}

enum Transport {
    private static var preferRelayUntil = Date.distantPast
    private static let lock = NSLock()
    static var lastWasRelay = false

    static func send(_ link: BridgeLink, method: String, path: String, headers: [String: String] = [:],
                     body: Data? = nil, timeout: Double = 6) async throws -> (Int, Data) {
        let relayReady = RelayConfig.stored?.on == true
        lock.lock(); let skipLAN = relayReady && preferRelayUntil > Date() && Date().timeIntervalSince(preferRelayUntil) > -15; lock.unlock()
        if !skipLAN {
            do {
                let r = try await lan(link, method, path, headers, body, relayReady ? min(timeout, 4) : timeout)
                lastWasRelay = false
                if path.hasPrefix("/api/info") == false { NetLog.add("LAN \(method) \(path) → \(r.0)") }
                return r
            } catch let e as URLError where relayReady && e.code != .cancelled {
                NetLog.add("LAN \(link.host) \(path) failed: \(e.code.rawValue) \(e.localizedDescription)")
                // Any network failure on the LAN path (cellular, VPN, other Wi-Fi): go through the relay.
                // Retry local Wi-Fi promptly after a transient failure.
                lock.lock(); preferRelayUntil = Date().addingTimeInterval(6); lock.unlock()
            }
        }
        do {
            let r = try await RelayClient.shared.request(method, path, headers: headers,
                                                         body: body.map { String(decoding: $0, as: UTF8.self) }, timeout: max(timeout, 10))
            lastWasRelay = true
            NetLog.add("Relay \(method) \(path) → \(r.0)")
            return r
        } catch {
            NetLog.add("Relay \(path) failed: \(error.localizedDescription)")
            throw error
        }
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
