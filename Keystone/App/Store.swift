import Foundation
import SwiftUI
import UIKit
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
    @Published var updateRunning = false

    private var pollTask: Task<Void, Never>?
    private var displayTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var displayEditedAt = Date.distantPast

    var isPaired: Bool { link.isSet }

    // MARK: Pairing

    @Published var pairStatus: String?

    func pair(host: String, port: Int) async throws {
        var i = try await BridgeAPI.info(host: host, port: port)
        var borrowedOwner = false
        if !i.supportsKeystone {
            // Old firmware only lets Afterglow update it. If Afterglow hasn't paired yet, borrow its slot,
            // update, and give the slot back afterwards.
            pairStatus = "This bridge has old firmware. Updating it first…"
            let owner = try await BridgeAPI.claimOwner(host: host, port: port)
            borrowedOwner = true
            guard let l = try await Firmware.latest(chip: i.chip ?? "esp32") else {
                throw BridgeError.message("Couldn't find the firmware on GitHub. Check your internet and try again.")
            }
            try await Firmware.install(l, link: BridgeLink(host: host, port: port, token: owner), header: "X-Afterglow-Token") { msg in
                Task { @MainActor in self.pairStatus = msg }
            }
            pairStatus = "Waiting for the bridge to restart…"
            var fresh: BridgeInfo?
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if let n = try? await BridgeAPI.info(host: host, port: port, timeout: 3), n.supportsKeystone { fresh = n; break }
            }
            guard let fresh else { throw BridgeError.message("The bridge didn't come back with the new firmware. Give it a minute and tap Pair again.") }
            i = fresh
        }
        pairStatus = "Pairing…"
        defer { pairStatus = nil }
        let token = try await BridgeAPI.claim(host: host, port: port)
        link = BridgeLink(host: host, port: port, token: token)
        BridgeLink.stored = link
        if borrowedOwner {
            // Free Afterglow's slot again so Afterglow can still pair to send lights.
            _ = try? await BridgeAPI.admin("resetPairing", ["app": "afterglow"], link)
        }
        apply(i)
        startPolling()
        if borrowedOwner { show("Updated the bridge and paired.") }
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
        guard let l = latest, !updateRunning else { return }
        updateRunning = true
        defer { updateRunning = false }
        updating = "Starting…"
        // The bridge's web server handles one request at a time: no status polling while the upload runs.
        stopPolling()
        defer { startPolling() }
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "firmware") { UIApplication.shared.endBackgroundTask(bg) }
        defer { UIApplication.shared.endBackgroundTask(bg) }
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

    static func install(_ latest: Latest, link: BridgeLink, header: String = "X-Device-Token", progress: @escaping (String) -> Void) async throws {
        progress("Downloading build \(latest.build)…")
        let (bin, resp) = try await URLSession.shared.data(from: latest.url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, bin.count > 100_000, bin.first == 0xE9 else {
            throw BridgeError.message("The download didn't look like ESP32 firmware.")
        }
        guard let u = BridgeAPI.url(link.host, link.port, "/api/update") else { throw BridgeError.message("Bad address.") }
        let boundary = "keystone-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"fw\"; filename=\"fw.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(bin)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 300
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(link.token, forHTTPHeaderField: header)
        req.setValue("close", forHTTPHeaderField: "Connection")
        // Its own session: one connection, nothing else queued to the bridge, long timeouts.
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = 1
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 600
        let session = URLSession(configuration: cfg)
        defer { session.finishTasksAndInvalidate() }
        var result: (Data, URLResponse)?
        var lastError: Error?
        for attempt in 1...3 {
            progress(attempt == 1 ? "Sending \(bin.count / 1024) KB to the bridge… keep Keystone open (about a minute)."
                                  : "Connection dropped. Trying again (\(attempt) of 3)…")
            do {
                result = try await session.upload(for: req, from: body)
                break
            } catch let e as URLError where [.networkConnectionLost, .timedOut, .cannotConnectToHost, .notConnectedToInternet].contains(e.code) {
                lastError = e
                try? await Task.sleep(nanoseconds: 4_000_000_000)   // let the bridge drop the half-finished upload
            }
        }
        guard let (data, r) = result else {
            throw BridgeError.message("The upload kept dropping (\(lastError?.localizedDescription ?? "unknown")). Stay close to the router and try again, or flash the full file over USB.")
        }
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw BridgeError.message("The bridge rejected Keystone's token.") }
        guard code == 200 else { throw BridgeError.message("Update failed: \(String(decoding: data, as: UTF8.self))") }
        progress("Installed. Restarting…")
    }
}
