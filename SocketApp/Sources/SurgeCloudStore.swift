import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// Cloud-only fallback for a power strip which can't speak the Tuya LAN
/// protocol (or when Keystone is offline). Cloud ≠ HomeKit/ESP32 pairing.
struct SurgeCloudDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let category: String
    let online: Bool
    let channels: [SurgeCloudChannel]

    static func parse(_ item: [String: Any]) -> SurgeCloudDevice? {
        guard let id = item["id"] as? String else { return nil }
        let name = (item["name"] as? String) ?? "Tuya device"
        let category = (item["category"] as? String) ?? ""
        var status: [String: Bool?] = [:]
        if let rows = item["status"] as? [[String: Any]] {
            for row in rows {
                guard let code = row["code"] as? String else { continue }
                status[code] = row["value"] as? Bool
            }
        } else if let dict = item["status"] as? [String: Any] {
            for (key, value) in dict { status[key] = value as? Bool }
        }
        // Never treat cloud list position as a Tuya DP number.
        let codes = status.keys.filter { code in
            if code == "switch" || code == "power" { return true }
            if code.hasPrefix("switch_usb") { return true }
            guard code.hasPrefix("switch_") else { return false }
            return Int(code.dropFirst("switch_".count)) != nil
        }.sorted {
            func order(_ code: String) -> Int {
                if code == "switch" || code == "power" { return 0 }
                if code.hasPrefix("switch_usb") {
                    return 100 + (Int(code.dropFirst("switch_usb".count).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))) ?? 1)
                }
                return Int(code.dropFirst("switch_".count)) ?? 999
            }
            return order($0) < order($1)
        }
        let hasIndividuals = codes.contains { code in
            code.hasPrefix("switch_usb") ||
            (code.hasPrefix("switch_") && Int(code.dropFirst("switch_".count)) != nil)
        }
        let selected = codes.filter { !hasIndividuals || ($0 != "switch" && $0 != "power") }
        let channels = selected.map { code -> SurgeCloudChannel in
            let title: String
            if code.hasPrefix("switch_usb") {
                let suffix = String(code.dropFirst("switch_usb".count)).trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
                title = suffix.isEmpty || suffix == "1" ? "USB" : "USB \(suffix)"
            } else if code.hasPrefix("switch_") {
                title = "Outlet \(code.dropFirst("switch_".count))"
            } else {
                title = "Master power (individual outlets unavailable)"
            }
            return SurgeCloudChannel(code: code, name: title, on: status[code] ?? nil)
        }
        let isPlug = ["pc", "cz"].contains(category) || name.localizedCaseInsensitiveContains("power") ||
                     name.localizedCaseInsensitiveContains("joly") || name.localizedCaseInsensitiveContains("strip")
        guard isPlug else { return nil }
        return SurgeCloudDevice(id: id, name: name, category: category,
                                online: (item["online"] as? Bool) ?? true, channels: channels)
    }
}

struct SurgeCloudChannel: Equatable {
    let code: String
    let name: String
    let on: Bool?
}

@MainActor
final class SurgeCloudStore: ObservableObject {
    static let shared = SurgeCloudStore()

    @Published var devices: [SurgeCloudDevice] = []
    @Published var selectedID: String
    @Published var protectedOutletIDs: Set<String>
    @Published var qrImage: UIImage?
    @Published var qr: String?
    @Published var userCode: String = ""
    @Published var busy: String?
    @Published var message: String?
    @Published var connected = false

    private var loginTask: Task<Void, Never>?
    private var client: TuyaClient?

    private init() {
        selectedID = UserDefaults.standard.string(forKey: "surge.tuya.deviceID") ?? ""
        protectedOutletIDs = Set(UserDefaults.standard.stringArray(forKey: "surge.protectedOutlets") ?? [])
    }

    var authorized: Bool { TuyaToken.stored != nil }
    var selected: SurgeCloudDevice? { devices.first { $0.id == selectedID } }
    var outlets: [SocketOutlet] {
        guard let selected else { return [] }
        return selected.channels.enumerated().map { (i, ch) in
            SocketOutlet(name: ch.name, dp: "cloud_" + ch.code, on: ch.on, index: i,
                         stripID: selected.id, code: ch.code)
        }
    }
    var hasProtectedOutlet: Bool { outlets.contains { protectedOutletIDs.contains($0.id) } }

    func select(_ id: String) {
        selectedID = id
        UserDefaults.standard.set(id, forKey: "surge.tuya.deviceID")
        SocketCache.write(outlets)
        message = nil
    }
    func setProtected(_ id: String, _ on: Bool) {
        if on { protectedOutletIDs.insert(id) } else { protectedOutletIDs.remove(id) }
        UserDefaults.standard.set(protectedOutletIDs.sorted(), forKey: "surge.protectedOutlets")
    }

    func load() async {
        guard let token = TuyaToken.stored else {
            connected = false
            return
        }
        busy = "load"
        defer { busy = nil }
        do {
            let api: TuyaClient
            if let client { api = client }
            else {
                api = TuyaClient(token: token)
                client = api
            }
            let raw = try await api.allDevicesRaw()
            let found = raw.compactMap(SurgeCloudDevice.parse).sorted { $0.name < $1.name }
            devices = found
            if found.count == 1 && selectedID.isEmpty { select(found[0].id) }
            if !selectedID.isEmpty && !found.contains(where: { $0.id == selectedID }) {
                selectedID = ""
                UserDefaults.standard.removeObject(forKey: "surge.tuya.deviceID")
            }
            connected = true
            if let selected {
                SocketCache.write(outlets)
                message = selected.channels.isEmpty
                    ? "Tuya returned this device but no confirmed outlet switch codes. This may be a master-only or cloud-limited product; no fake channels were created."
                    : nil
            } else if found.isEmpty {
                message = "No power strip or compatible plug appeared in this Tuya Smart account. Confirm the device is in the account used to scan the QR."
            }
        } catch {
            connected = false
            message = "Tuya Smart couldn't refresh its device list: \(error.localizedDescription). QR authorization is kept."
        }
    }

    func control(_ id: String, action: SocketAction) async throws {
        guard let token = TuyaToken.stored,
              let selected,
              let outlet = outlets.first(where: { $0.id == id }),
              let code = outlet.code,
              let channel = selected.channels.first(where: { $0.code == code }) else {
            throw SocketFailure(message: "The selected Tuya Smart channel is no longer available; refresh the device list.")
        }
        let on: Bool
        switch action {
        case .on: on = true
        case .off: on = false
        case .toggle:
            guard let old = channel.on else {
                throw SocketFailure(message: "Tuya did not provide this channel's current state. Choose On or Off explicitly.")
            }
            on = !old
        }
        let api: TuyaClient
        if let client { api = client } else { api = TuyaClient(token: token); client = api }
        try await api.sendCloudSwitch(deviceID: selected.id, code: code, on: on)
        message = "Tuya Smart accepted the \(on ? "on" : "off") command for \(channel.name). Delivery is not yet confirmed."
        await load()
    }

    func all(_ on: Bool) async throws {
        guard let device = selected, connected else {
            throw SocketFailure(message: "Select an online Tuya Smart power strip first.")
        }
        let sockets = outlets
        if !on && !hasProtectedOutlet {
            throw SocketFailure(message: "Before All Off, protect the outlet supplying Keystone/HomePod using the shield beside that outlet. This prevents accidentally shutting down the bridge.")
        }
        var errors: [String] = []
        for outlet in sockets where on || !protectedOutletIDs.contains(outlet.id) {
            do { try await control(outlet.id, action: on ? .on : .off) }
            catch { errors.append(outlet.name) }
        }
        if !errors.isEmpty {
            throw SocketFailure(message: "Tuya Smart could not command: \(errors.joined(separator: ", ")).")
        }
        message = "Tuya accepted commands for \(device.name). Check actual outlet state in Tuya Smart."
    }

    func requestQR() async {
        busy = "qr"
        message = nil
        defer { busy = nil }
        let code = userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { message = "Enter the Tuya Smart user code first."; return }
        do {
            let value = try await TuyaLogin.requestQR(userCode: code)
            qr = value
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data((TuyaConst.qrPrefix + value).utf8)
            filter.correctionLevel = "Q"
            guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
                  let cg = CIContext().createCGImage(output, from: output.extent) else {
                throw SocketFailure(message: "Could not render the Tuya login QR.")
            }
            qrImage = UIImage(cgImage: cg)
            startPolling(value, userCode: code)
        } catch { message = error.localizedDescription }
    }

    private func startPolling(_ qr: String, userCode: String) {
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            let started = Date()
            while !Task.isCancelled && Date().timeIntervalSince(started) < 285 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                do {
                    if let auth = try await TuyaLogin.poll(qr: qr, userCode: userCode) {
                        TuyaToken.stored = auth
                        self?.qr = nil
                        self?.qrImage = nil
                        self?.client = TuyaClient(token: auth)
                        self?.message = "Tuya Smart authorized. Choose your power strip."
                        await self?.load()
                        return
                    }
                } catch {
                    self?.message = "Tuya login polling: \(error.localizedDescription)"
                }
            }
            self?.message = "Tuya login QR expired; request a new one."
            self?.qr = nil
            self?.qrImage = nil
        }
    }

    func restartLogin() {
        loginTask?.cancel()
        qr = nil
        qrImage = nil
        message = nil
    }
    func signOut() {
        restartLogin()
        TuyaToken.stored = nil
        client = nil
        devices = []
        connected = false
        message = "Tuya Smart disconnected. Keystone pairing was not changed."
    }
    func openTuyaApp() {
        guard let url = URL(string: "tuyaSmart://") else { return }
        UIApplication.shared.open(url) { opened in
            if !opened, let store = URL(string: "https://apps.apple.com/ca/app/id1034649547") {
                UIApplication.shared.open(store)
            }
        }
    }
}
