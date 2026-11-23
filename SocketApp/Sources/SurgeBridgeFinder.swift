import Foundation
import Network

/// Finds the *Keystone ESP32*, not the Tuya power strip, using Keystone's existing Bonjour service.
@MainActor
final class SurgeBridgeFinder: ObservableObject {
    struct Bridge: Hashable {
        let name: String
        let host: String
        let port: Int
    }
    @Published var found: [Bridge] = []
    @Published var searching = false
    private var browser: NWBrowser?

    func start() {
        stop()
        searching = true
        found = []
        let browser = NWBrowser(for: .bonjour(type: "_afterglow._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for item in results {
                guard case .service(let name, _, _, _) = item.endpoint else { continue }
                Task { await self?.resolve(item.endpoint, name: name) }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.searching = false
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        searching = false
    }

    private func resolve(_ endpoint: NWEndpoint, name: String) async {
        let params = NWParameters.tcp
        if let v4 = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            v4.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: params)
        let foundEndpoint: (String, Int)? = await withCheckedContinuation { continuation in
            let once = SurgeOnce()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint,
                       once.fire() {
                        var value = "\(host)"
                        if let percent = value.firstIndex(of: "%") {
                            value = String(value[..<percent])
                        }
                        continuation.resume(returning: (value, Int(port.rawValue)))
                    } else if once.fire() {
                        continuation.resume(returning: nil)
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    if once.fire() { continuation.resume(returning: nil) }
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                if once.fire() {
                    continuation.resume(returning: nil)
                    connection.cancel()
                }
            }
        }
        guard let result = foundEndpoint,
              !found.contains(where: { $0.host == result.0 }) else { return }
        found.append(Bridge(name: name, host: result.0, port: result.1))
    }
}

final class SurgeOnce: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func fire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
