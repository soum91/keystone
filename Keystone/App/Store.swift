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
    @Published var relay = RelayConfig.stored
    @Published var viaRelay = false
    @Published var lastError: String?
    @Published var forgotten = false
    @Published var scenes = KScene.stored
    @Published var runningScene: UUID?   // the bridge was reset and no longer knows this phone

    private var pollTask: Task<Void, Never>?
    private var displayTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var displayEditedAt = Date.distantPast
    private var lastFullInfoAt = Date.distantPast

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
        var token: String
        do {
            token = try await BridgeAPI.claim(host: host, port: port, name: Store.phoneName)
        } catch BridgeError.alreadyPaired {
            // Keystone was deleted or reinstalled, so its old key is gone but the bridge remembers the pairing.
            // If Afterglow isn't paired, borrow its slot to clear the stale Keystone pairing, then pair again.
            pairStatus = "Clearing the old Keystone pairing…"
            let owner: String
            do {
                owner = try await BridgeAPI.claimOwner(host: host, port: port)
            } catch {
                throw BridgeError.message("The bridge still remembers an older Keystone pairing, and Afterglow is paired so Keystone can't clear it itself. In Afterglow › Settings › Apple Home bridge, tap Reset Keystone pairing, then pair here.")
            }
            borrowedOwner = true
            try await BridgeAPI.resetKeystone(host: host, port: port, ownerToken: owner)
            token = try await BridgeAPI.claim(host: host, port: port, name: Store.phoneName)
        }
        link = BridgeLink(host: host, port: port, token: token)
        BridgeLink.stored = link
        if borrowedOwner {
            // Free Afterglow's slot again so Afterglow can still pair to send lights.
            _ = try? await BridgeAPI.admin("resetPairing", ["app": "afterglow"], link)
        }
        apply(i)
        await fetchRelay()
        startPolling()
        if borrowedOwner { show("Paired.") }
    }

    /// After the bridge was reset: claim a fresh token at the same address, keeping everything else.
    func repair() async {
        do {
            let token = try await BridgeAPI.claim(host: link.host, port: link.port, name: Store.phoneName)
            link.token = token
            BridgeLink.stored = link
            forgotten = false
            await fetchRelay()
            await refresh()
            show("Paired again. Remote access is set up for this phone.")
        } catch BridgeError.alreadyPaired {
            show("Keystone is already paired on 4 phones. Forget one under Bridge › Phones using Keystone (from a paired phone), or hold BOOT on the bridge for 8 s, then try again.")
        } catch {
            show("Do this at home on the bridge's Wi-Fi: \(error.localizedDescription)")
        }
    }

    /// How this phone shows up in the bridge's list of paired phones.
    static var phoneName: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return "\(UIDevice.current.name) · paired \(f.string(from: Date()))"
    }

    func forget() {
        let old = link
        if !old.token.isEmpty { Task { await BridgeAPI.unpair(old) } }   // free this phone's slot on the bridge
        stopPolling()
        link = BridgeLink()
        BridgeLink.stored = link
        RelayConfig.stored = nil
        relay = nil
        Task { await RelayClient.shared.disconnect() }
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
                let away = await self?.viaRelay ?? false
                try? await Task.sleep(nanoseconds: away ? 6_000_000_000 : 3_000_000_000)
            }
        }
        if latest == nil { Task { await checkFirmware() } }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        Task { await RelayClient.shared.disconnect() }   // iOS kills it in the background anyway; start clean
    }

    func refresh() async {
        guard isPaired else { return }
        do {
            // Keep frequent status polling small; get full activity/events every 30 s.
            let needFull = Date().timeIntervalSince(lastFullInfoAt) >= 30
            var i = try await BridgeAPI.info(link, timeout: 3, lite: !needFull)
            if needFull { lastFullInfoAt = .now }
            if i.events == nil { i.events = info?.events }
            if i.bar?.events == nil { i.bar?.events = info?.bar?.events }
            viaRelay = Transport.lastWasRelay
            lastError = nil
            apply(i)
            forgotten = i.auth == false
            // At home: pick up the relay key (or a new one after a reset) so remote access works when away.
            if !viaRelay, !forgotten, let r = i.remote,
               relay == nil || relay?.on != r.on || (r.id != nil && relay?.id != r.id) { await fetchRelay() }
        } catch {
            reachable = false
            lastError = error.localizedDescription
        }
    }

    // MARK: Remote access

    func fetchRelay() async {
        guard let c = try? await BridgeAPI.relayConfig(link) else { return }
        if c != relay {
            RelayConfig.stored = c
            relay = c
            await RelayClient.shared.disconnect()
        }
    }

    @Published var relayTest: String?

    /// Round trip through the relay even at home, so remote access can be checked before leaving.
    func testRelay() async {
        relayTest = "Testing…"
        if !viaRelay { await fetchRelay() }
        // At home the bridge's own counters (read over Wi-Fi) tell which leg failed.
        let before = viaRelay ? nil : (try? await BridgeAPI.info(host: link.host, port: link.port))?.remote
        let t0 = Date()
        do {
            let (code, data) = try await RelayClient.shared.request("GET", "/api/info?lite=1", headers: ["X-Device-Token": link.token], body: nil, timeout: 15)
            let ok = code == 200 && (try? JSONDecoder().decode(BridgeInfo.self, from: data)) != nil
            relayTest = ok ? String(format: "Works: the bridge answered through the relay in %.1f s.", Date().timeIntervalSince(t0))
                           : "The bridge answered, but with HTTP \(code)."
        } catch {
            var why = "Failed: \(error.localizedDescription)"
            if let b = before, let a = (try? await BridgeAPI.info(host: link.host, port: link.port))?.remote {
                let heard = (a.heard ?? 0) - (b.heard ?? 0), sent = (a.served ?? 0) - (b.served ?? 0)
                if (a.heard ?? 0) < (b.heard ?? 0) {
                    why += " The bridge restarted during the test."
                } else if heard <= 0 {
                    why += " The bridge never got the request: the relay didn't pass it on (bridge relay: \(a.connected == true ? "connected" : (a.error ?? "not connected")))."
                } else if sent <= 0 {
                    why += " The bridge got the request but couldn't send its answer (\(a.error ?? "no reason given"))."
                } else {
                    why += " The bridge got it and answered (\(a.replyBytes ?? 0) bytes in \(a.replyMs ?? 0) ms), but the answer never reached this phone."
                }
                NetLog.add("relay test: heard +\(heard), answered +\(sent), reply \(a.replyBytes ?? 0) B / \(a.replyMs ?? 0) ms")
            }
            relayTest = why
        }
        await refresh()
    }

    func setRemote(on: Bool? = nil, rotate: Bool = false) async {
        var body: [String: Any] = [:]
        if let on { body["on"] = on }
        if rotate { body["rotate"] = true }
        do {
            if let c = try await BridgeAPI.setRelay(body, link) {
                RelayConfig.stored = c
                relay = c
                await RelayClient.shared.disconnect()
                show(rotate ? "New key. Other phones need to open Keystone at home once." : (c.on ? "Remote access on." : "Remote access off."))
            }
            await refresh()
        } catch {
            show(error.localizedDescription)
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
        if (i.lights ?? []).count > 0 { seedScenes(i) }
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
                let r = try await BridgeAPI.setDisplay(snapshot, self?.link ?? .stored)
                if let on = r["on"] as? Bool, on != snapshot.on {
                    self?.show("The bridge didn't take the change (screen is still \(on ? "on" : "off")).")
                    self?.display.on = on
                }
            } catch {
                self?.show("Couldn't change the screen: \(error.localizedDescription)")
                self?.displayEditedAt = .distantPast   // show the bridge's real setting again on the next refresh
            }
        }
    }

    func identify() async {
        do { try await BridgeAPI.post("/api/identify", [:], link); show("Look at the bridge: its screen says hello for 8 s.") }
        catch { show(error.localizedDescription) }
    }

    // MARK: Scenes

    func runScene(_ s: KScene) async {
        runningScene = s.id
        let failed = await KScene.run(s, link: link)
        runningScene = nil
        show(failed.isEmpty ? "\(s.name) is set." : "Couldn't do: \(failed.joined(separator: ", "))")
        await refresh()
    }

    func saveScene(_ s: KScene) {
        if let i = scenes.firstIndex(where: { $0.id == s.id }) { scenes[i] = s } else { scenes.append(s) }
        KScene.stored = scenes
        KeystoneShortcuts.updateAppShortcutParameters()
    }

    func deleteScene(_ s: KScene) {
        scenes.removeAll { $0.id == s.id }
        KScene.stored = scenes
        KeystoneShortcuts.updateAppShortcutParameters()
    }

    /// The first time the bridge is seen: a few scenes to start from.
    private func seedScenes(_ i: BridgeInfo) {
        guard scenes.isEmpty, !UserDefaults.standard.bool(forKey: "scenesSeeded") else { return }
        let st = KScene.starters(i)
        guard !st.isEmpty else { return }
        UserDefaults.standard.set(true, forKey: "scenesSeeded")
        scenes = st
        KScene.stored = st
        KeystoneShortcuts.updateAppShortcutParameters()
    }

    // MARK: Control (LAN or relay)

    func control(_ body: [String: Any]) async {
        do {
            try await BridgeAPI.post("/api/control", body, link, timeout: 8)
            try? await Task.sleep(nanoseconds: 700_000_000)
            await refresh()
        } catch {
            show(error.localizedDescription)
        }
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
        guard !updateRunning else { return }
        // Always ask GitHub again first: a newer build replaces the old download link.
        if let chip = info?.chip, let fresh = try? await Firmware.latest(chip: chip) { latest = fresh }
        guard let l = latest else { updating = "Couldn't reach GitHub to find the firmware. Check your internet and try again."; return }
        if l.build <= (info?.build ?? 0) { updating = "Already up to date (build \(info?.build ?? 0))."; return }
        if viaRelay {
            guard info?.remoteOta?.supported == true else {
                updating = "Update the bridge once while on home Wi-Fi to enable future internet OTA."
                return
            }
            updateRunning = true
            defer { updateRunning = false }
            updating = "Requesting internet OTA for build \(l.build)…"
            do {
                let response = try await BridgeAPI.post("/api/ota/remote", ["build": l.build], link, timeout: 15)
                guard response["queued"] as? Bool == true else {
                    throw BridgeError.message("Bridge did not confirm remote OTA request.")
                }
                updating = "Queued build \(l.build). ESP32 will restart, download from GitHub and verify SHA-256."
                // Relay disconnects while flashing. Only announce completion
                // once status reports the new installed build after reboot.
                for _ in 0..<36 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    await refresh()
                    if (info?.build ?? 0) >= l.build {
                        updating = "Verified: bridge updated to build \(l.build)."
                        return
                    }
                    if info?.remoteOta?.state == "failed" {
                        updating = "Internet OTA failed: \(info?.remoteOta?.error ?? "unknown error"). The bridge has returned to normal mode; retry when the reported cause is resolved."
                        return
                    }
                }
                updating = "Request queued, but the bridge has not confirmed installation. Check again when the relay reconnects."
            } catch {
                updating = "Remote update request failed: \(error.localizedDescription)"
            }
            return
        }
        updateRunning = true
        defer { updateRunning = false }
        updating = "Starting…"
        // The bridge's web server handles one request at a time: no status polling while the upload runs.
        stopPolling()
        defer { startPolling() }
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "firmware") { UIApplication.shared.endBackgroundTask(bg) }
        defer { UIApplication.shared.endBackgroundTask(bg) }
        // A locked screen suspends the upload mid-way. Keep the phone awake until it's done.
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = false }
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
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/soum91/keystone/releases/tags/firmware-latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = obj["assets"] as? [[String: Any]] else { return nil }
        // Concurrent release jobs can briefly leave multiple assets in firmware-latest.
        // Always choose the highest valid build, not the first asset returned by GitHub.
        var newest: Latest?
        for a in assets {
            guard let name = a["name"] as? String, name.hasSuffix("-app.bin"),
                  let prefix = ["KeystoneBridge-\(chip)-build-", "AfterglowBridge-\(chip)-build-"].first(where: { name.hasPrefix($0) }),
                  let n = Int(name.dropFirst(prefix.count).dropLast("-app.bin".count)),
                  let s = a["browser_download_url"] as? String, let u = URL(string: s) else { continue }
            if newest == nil || n > newest!.build { newest = Latest(build: n, url: u) }
        }
        return newest
    }

    static func install(_ latest: Latest, link: BridgeLink, header: String = "X-Device-Token", progress: @escaping (String) -> Void) async throws {
        progress("Downloading build \(latest.build)…")
        let (bin, resp) = try await URLSession.shared.data(from: latest.url)
        let dlCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard dlCode == 200 else {
            throw BridgeError.message("GitHub answered \(dlCode) for build \(latest.build). Tap Check for updates and try again.")
        }
        guard bin.count > 100_000, bin.first == 0xE9 else {
            throw BridgeError.message("The download (\(bin.count / 1024) KB) wasn't ESP32 firmware. Tap Check for updates and try again.")
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
        let attempts = 4
        // Prefer the bridge's isolated upload-only boot (firmware 1.11.12+).
        // HomeSpan, the 24-KB worker, Govee and cloud/TLS clients are absent,
        // so the WebServer can receive the binary without competing for RAM.
        // Firmware 1.11.11 and earlier don't know "prepareUpdate": use their
        // original restart-and-upload path for backward compatibility.
        func localMaintenanceReady() async -> Bool {
            guard let endpoint = BridgeAPI.url(link.host, link.port, "/api/ota/local") else { return false }
            var check = URLRequest(url: endpoint)
            check.timeoutInterval = 3
            check.cachePolicy = .reloadIgnoringLocalCacheData
            check.setValue(link.token, forHTTPHeaderField: "X-Device-Token")
            guard let (data, response) = try? await URLSession.shared.data(for: check),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return obj["ready"] as? Bool == true && obj["mode"] as? String == "isolated"
        }
        func freshBoot(_ attempt: Int) async -> Bool {
            progress(attempt == 1 ? "Preparing a low-memory firmware upload…"
                                  : "Preparing another firmware upload (\(attempt) of \(attempts))…")
            let prepared = (try? await BridgeAPI.postLocal("/api/admin",
                                                             ["action": "prepareUpdate"],
                                                             link, timeout: 7))?["restart"] as? Bool == true
            if prepared {
                progress("Bridge is entering isolated upload mode (HomeKit and cloud services paused)…")
                for _ in 0..<45 { // 90 s allows Wi-Fi to reconnect after the one-shot reboot
                    if await localMaintenanceReady() { return true }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
                lastError = BridgeError.message("Bridge acknowledged isolated OTA but its upload-only server did not become reachable. It returns to normal mode automatically; check Wi-Fi and try again.")
                return false
            }
            // A timed-out acknowledgment could still have triggered the reboot.
            for _ in 0..<3 {
                if await localMaintenanceReady() { return true }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            progress("This firmware uses the older, memory-limited upload method…")
            _ = try? await BridgeAPI.admin("restart", [:], link)
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            for _ in 0..<30 {
                if let i = try? await BridgeAPI.info(host: link.host, port: link.port, timeout: 3),
                   (i.uptime ?? 99) < 60 { return true }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            lastError = BridgeError.message("Bridge did not return to the local upload service after restarting.")
            return false
        }
        for attempt in 1...attempts {
            guard await freshBoot(attempt) else {
                lastError = BridgeError.message("the bridge didn't come back after restarting")
                break
            }
            progress("Sending \(bin.count / 1024) KB to the bridge… keep Keystone open with the screen on.")
            do {
                result = try await session.upload(for: req, from: body)
                break
            } catch let e as URLError where [.networkConnectionLost, .timedOut, .cannotConnectToHost, .notConnectedToInternet, .cannotFindHost].contains(e.code) {
                lastError = e
                progress("Connection dropped. Waiting for the bridge…")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        guard let (data, r) = result else {
            throw BridgeError.message("The upload kept dropping (\(lastError?.localizedDescription ?? "unknown")). Keep Keystone open with the screen on, stay close to the router and try again, or flash the full file over USB.")
        }
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw BridgeError.message("The bridge rejected Keystone's token.") }
        guard code == 200 else { throw BridgeError.message("Update failed: \(String(decoding: data, as: UTF8.self))") }
        progress("Installed. Restarting…")
    }
}
