import Foundation
import Security
import SwiftUI

struct SocketOutlet: Codable, Hashable, Identifiable {
    let name: String
    let dp: String
    let on: Bool?
    let index: Int
    let stripID: String
    var id: String { stripID + ":" + dp }
    var powersBridge: Bool { name.localizedCaseInsensitiveContains("keystone") }
}
struct StripStatus: Decodable {
    let configured: Bool?
    let id: String?
    let name: String?
    let ip: String?
    let ok: Bool?
    let error: String?
    let outlets: [Outlet]?
    struct Outlet: Decodable { let name: String; let dp: String; let on: Bool? }
    var sockets: [SocketOutlet] {
        (outlets ?? []).enumerated().map {
            SocketOutlet(name: $0.element.name, dp: $0.element.dp, on: $0.element.on,
                         index: $0.offset, stripID: id ?? "")
        }
    }
}
struct BridgeState: Decodable {
    let app: String
    let build: Int?
    let version: String?
    let ip: String?
    let name: String?
    let strip: StripStatus?
}
struct PairState: Decodable { let token: String }
struct BridgeResponseError: Decodable { let error: String? }
struct SocketFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
enum SocketCache {
    private static let key = "socket.cached.outlets"
    static func read() -> [SocketOutlet] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SocketOutlet].self, from: data)) ?? []
    }
    static func write(_ list: [SocketOutlet]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}
enum SocketSecret {
    private static let service = "com.soum91.socket"
    private static let account = "keystone"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func read() -> String? {
        var q = query
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw SocketFailure(message: "Could not save pairing in Keychain: \(status)") }
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
}
enum SocketAPI {
    static func send(host: String, port: Int, token: String?, path: String,
                     body: [String: Any]? = nil) async throws -> Data {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !host.contains("/"), !host.contains("@"), (1...65535).contains(port),
              let url = URL(string: "http://\(host):\(port)\(path)") else {
            throw SocketFailure(message: "Enter the bridge's LAN IP address.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token { request.setValue(token, forHTTPHeaderField: "X-Device-Token") }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if path.hasPrefix("/api/dev/") { request.httpMethod = "POST" }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SocketFailure(message: "Keystone did not answer at \(host):\(port). That may be the power strip's IP rather than the ESP32's. Select a discovered Keystone bridge on your Wi-Fi. (\(error.localizedDescription))")
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let message = (try? JSONDecoder().decode(BridgeResponseError.self, from: data))?.error
            throw SocketFailure(message: message ?? "Keystone returned HTTP \(code).")
        }
        return data
    }
}
@MainActor final class SocketStore: ObservableObject {
    static let shared = SocketStore()
    @Published var host: String
    @Published var port: Int
    @Published var token: String?
    @Published var strip: StripStatus?
    @Published var reachable = false
    @Published var message: String?
    @Published var busy: String?
    private init() {
        host = UserDefaults.standard.string(forKey: "socket.host") ?? ""
        let n = UserDefaults.standard.integer(forKey: "socket.port")
        port = (1...65535).contains(n) ? n : 8080
        token = SocketSecret.read()
    }
    var paired: Bool { token != nil }
    var sockets: [SocketOutlet] { strip?.sockets ?? SocketCache.read() }
    func pair() async {
        busy = "pair"; message = nil
        defer { busy = nil }
        do {
            let result = try await SocketAPI.send(host: host, port: port, token: nil, path: "/api/info?lite=1")
            let status = try JSONDecoder().decode(BridgeState.self, from: result)
            guard status.app == "afterglow-bridge" else {
                throw SocketFailure(message: "That address is not a Keystone bridge. Use the bridge shown by discovery, not the Joly Joy device IP.")
            }
            if let build = status.build, build < 175 {
                throw SocketFailure(message: "Keystone bridge firmware build \(build) is too old for Surge pairing. Open Keystone → Bridge → Firmware and update to build 175 or newer. Your HomeKit pairing is preserved.")
            }
            let reply: Data
            do {
                reply = try await SocketAPI.send(host: host, port: port, token: nil,
                                                 path: "/api/dev/claim?app=socket&name=Surge")
            } catch {
                if error.localizedDescription.localizedCaseInsensitiveContains("unknown app") {
                    throw SocketFailure(message: "This Keystone bridge responds, but its installed firmware does not know Surge yet. In Keystone → Bridge → Firmware update to build 175 or newer, then pair again. The device IP in Joly Joy is not the bridge IP.")
                }
                throw error
            }
            let value = try JSONDecoder().decode(PairState.self, from: reply).token
            try SocketSecret.save(value)
            token = value
            host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(host, forKey: "socket.host")
            UserDefaults.standard.set(port, forKey: "socket.port")
            await refresh()
            message = strip?.configured == true ? "Surge paired with Keystone." : "Surge paired. Now configure the separate channels in Keystone → Bridge → Power strip."
        } catch { message = error.localizedDescription }
    }
    func refresh() async {
        guard !host.isEmpty else { return }
        do {
            let data = try await SocketAPI.send(host: host, port: port, token: token, path: "/api/info?lite=1")
            let info = try JSONDecoder().decode(BridgeState.self, from: data)
            guard info.app == "afterglow-bridge" else { throw SocketFailure(message: "Not a Keystone bridge.") }
            strip = info.strip
            reachable = true
            if let strip, strip.configured == true { SocketCache.write(strip.sockets) }
        } catch {
            reachable = false
            message = error.localizedDescription
        }
    }
    func control(id: String, action: SocketAction) async throws {
        guard let token else { throw SocketFailure(message: "Pair Socket with Keystone first.") }
        // Resolve the identifier against the current bridge mapping to avoid stale channel indices.
        let data = try await SocketAPI.send(host: host, port: port, token: token, path: "/api/info?lite=1")
        let current = try JSONDecoder().decode(BridgeState.self, from: data).strip
        guard let current, current.configured == true,
              let target = current.sockets.first(where: { $0.id == id }) else {
            throw SocketFailure(message: "That socket is no longer configured.")
        }
        let on: Bool
        switch action {
        case .on: on = true
        case .off: on = false
        case .toggle:
            guard let state = target.on else { throw SocketFailure(message: "Socket state is unknown; refresh first.") }
            on = !state
        }
        _ = try await SocketAPI.send(host: host, port: port, token: token, path: "/api/control",
                                     body: ["device": "strip", "outlet": target.index, "on": on])
        await refresh()
    }
    func all(_ on: Bool) async throws {
        guard let token else { throw SocketFailure(message: "Pair Socket with Keystone first.") }
        let data = try await SocketAPI.send(host: host, port: port, token: token, path: "/api/info?lite=1")
        guard let s = try JSONDecoder().decode(BridgeState.self, from: data).strip, s.configured == true else {
            throw SocketFailure(message: "No strip has been configured in Keystone.")
        }
        if on {
            _ = try await SocketAPI.send(host: host, port: port, token: token,
                                         path: "/api/control", body: ["device": "strip", "all": true])
        } else {
            for outlet in s.sockets where !outlet.powersBridge {
                _ = try await SocketAPI.send(host: host, port: port, token: token,
                                             path: "/api/control",
                                             body: ["device": "strip", "outlet": outlet.index, "on": false])
            }
        }
        await refresh()
    }
    func flip(_ s: SocketOutlet, to on: Bool) async {
        busy = s.id; message = nil
        defer { busy = nil }
        do { try await control(id: s.id, action: on ? .on : .off) }
        catch { message = error.localizedDescription }
    }
    func flipAll(to on: Bool) async {
        busy = "all"; message = nil
        defer { busy = nil }
        do { try await all(on) }
        catch { message = error.localizedDescription }
    }
    func forget() async {
        if let token {
            _ = try? await SocketAPI.send(host: host, port: port, token: token,
                                          path: "/api/dev/unpair?app=socket")
        }
        SocketSecret.remove()
        token = nil
        strip = nil
        reachable = false
        SocketCache.write([])
        message = "Surge is unpaired. Apple Home and Keystone remain unchanged."
    }
}
