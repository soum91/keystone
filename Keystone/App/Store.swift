import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var link = BridgeLink.stored
    @Published var info: BridgeInfo? = Snapshot.stored?.info
    @Published var lastSeen: Date? = Snapshot.stored?.at
    @Published var reachable = false
    @Published var display = DisplaySettings()
    @Published var toast: String?
    @Published var latest: Firmware.Latest?
    @Published var updating: String?

    private var pollTask: Task<Void, Never>?
    private var displayTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var displayEditedAt = Date.distantPast

    var isPaired: Bool { link.isSet }

    // MARK: Pairing

    func pair(host: String, port: Int) async throws {
        let i = try await BridgeAPI.info(host: host, port: port)
        guard i.supportsKeystone else {
            throw BridgeError.message("This bridge firmware is too old for Keystone. Update it once from Afterglow (Settings › Apple Home bridge › Firmware), then pair here.")
        }
        let token = try await BridgeAPI.claim(host: host, port: port)
        link = BridgeLink(host: host, port: port, token: token)
        BridgeLink.stored = link
        apply(i)
        startPolling()
    }

    func forget() {
        stopPolling()
        link = BridgeLink()
        BridgeLink.stored = link
        info = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Polling

    func startPolling() {
        guard isPaired else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        if latest == nil { Task { await checkFirmware() } }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard isPaired else { return }
        do {
            let i = try await BridgeAPI.info(link, timeout: 3)
            apply(i)
        } catch {
            reachable = false
        }
    }

    private func apply(_ i: BridgeInfo) {
        let changedForWidget = info?.govee != i.govee || info?.tv?.state != i.tv?.state || info?.lightsOn != i.lightsOn
        info = i
        reachable = true
        lastSeen = .now
        // Don't fight the sliders while someone is moving them.
        if let d = i.display, Date().timeIntervalSince(displayEditedAt) > 4 { display = d }
        Snapshot.stored = Snapshot(info: i, at: .now)
        if changedForWidget { WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: Display

    /// Optimistic, debounced: the UI changes now, the bridge gets the last value after a short pause.
    func setDisplay(_ change: (inout DisplaySettings) -> Void) {
        change(&display)
        displayEditedAt = .now
        displayTask?.cancel()
        let snapshot = display
        displayTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            do {
                try await BridgeAPI.setDisplay(snapshot, self?.link ?? .stored)
            } catch {
                self?.show(error.localizedDescription)
            }
        }
    }

    func identify() async {
        do { try await BridgeAPI.post("/api/identify", [:], link); show("Look at the bridge: its screen says hello for 8 s.") }
        catch { show(error.localizedDescription) }
    }

    // MARK: Admin

    func admin(_ action: String, _ extra: [String: Any] = [:], done: String) async {
        do {
            let restart = try await BridgeAPI.admin(action, extra, link)
            show(restart ? "\(done) The bridge is restarting (about 20 s)." : done)
            if restart { reachable = false }
            await refresh()
        } catch {
            show(error.localizedDescription)
        }
    }

    func setFollow(lights: Bool? = nil, bar: Bool? = nil) async {
        var extra: [String: Any] = [:]
        if let lights { extra["lights"] = lights }
        if let bar { extra["bar"] = bar }
        await admin("follow", extra, done: "Saved.")
    }

    // MARK: Firmware

    func checkFirmware() async {
        guard let chip = info?.chip else { return }
        latest = try? await Firmware.latest(chip: chip)
    }

    var updateAvailable: Bool {
        guard let l = latest else { return false }
        return l.build > (info?.build ?? 0)
    }

    func installUpdate() async {
        guard let l = latest else { return }
        updating = "Starting…"
        do {
            try await Firmware.install(l, link: link) { msg in Task { @MainActor in self.updating = msg } }
            reachable = false
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await refresh()
                if reachable, (info?.build ?? 0) >= l.build { break }
            }
            updating = (info?.build ?? 0) >= l.build ? "Updated to build \(l.build)." : "Sent. If the build doesn't change in a minute, pull to refresh."
        } catch {
            updating = error.localizedDescription
        }
    }

    // MARK: Messages

    func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}

/// Firmware updates: the phone fetches the right .bin from GitHub and uploads it to the bridge over Wi-Fi.
enum Firmware {
    struct Latest: Equatable { var build: Int; var url: URL }

    static func latest(chip: String) async throws -> Latest? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/soum91/afterglow/releases/tags/firmware-latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = obj["assets"] as? [[String: Any]] else { return nil }
        let prefix = "AfterglowBridge-\(chip)-build-"
        for a in assets {
            guard let name = a["name"] as? String, name.hasPrefix(prefix), name.hasSuffix("-app.bin"),
                  let n = Int(name.dropFirst(prefix.count).dropLast("-app.bin".count)),
                  let s = a["browser_download_url"] as? String, let u = URL(string: s) else { continue }
            return Latest(build: n, url: u)
        }
        return nil
    }

    static func install(_ latest: Latest, link: BridgeLink, progress: @escaping (String) -> Void) async throws {
        progress("Downloading build \(latest.build)…")
        let (bin, resp) = try await URLSession.shared.data(from: latest.url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, bin.count > 100_000, bin.first == 0xE9 else {
            throw BridgeError.message("The download didn't look like ESP32 firmware.")
        }
        progress("Sending \(bin.count / 1024) KB to the bridge… keep Keystone open.")
        guard let u = BridgeAPI.url(link.host, link.port, "/api/update") else { throw BridgeError.message("Bad address.") }
        let boundary = "keystone-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"fw\"; filename=\"fw.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(bin)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(link.token, forHTTPHeaderField: "X-Device-Token")
        let (data, r) = try await URLSession.shared.upload(for: req, from: body)
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw BridgeError.message("The bridge rejected Keystone's token.") }
        guard code == 200 else { throw BridgeError.message("Update failed: \(String(decoding: data, as: UTF8.self))") }
        progress("Installed. Restarting…")
    }
}
