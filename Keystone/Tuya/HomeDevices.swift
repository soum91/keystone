import Foundation

/// A Smart Life light, switch or plug that Keystone can put in Apple Home through the bridge.
/// The bridge talks to it over Wi-Fi with its local key, so it needs the device's address (found by scanning).
struct HomeDevice: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var category: String
    var productName: String
    var online: Bool
    var localKey: String?
    var statusCodes: [String] = []
    var ranges: [String: TuyaRange] = [:]
    /// Local data point id -> cloud code.
    var dpMap: [String: String] = [:]
    var host: String?
    var version: Double?
    var inHome = false

    // Same lists as Afterglow.
    static let lightCategories: Set<String> = ["dj", "dd", "xdd", "fwd", "dc", "tgq", "tyndj", "sxd", "gyd", "fsd", "mbd", "tgkg"]
    static let switchCategories: Set<String> = ["kg", "cz", "tdq", "kgq", "dlq", "znjdq"]   // "pc" strips have their own screen

    static func parse(_ d: [String: Any]) -> HomeDevice? {
        guard let id = d["id"] as? String else { return nil }
        var codes: [String] = []
        if let list = d["status"] as? [[String: Any]] { codes = list.compactMap { $0["code"] as? String } }
        else if let dict = d["status"] as? [String: Any] { codes = Array(dict.keys) }
        return HomeDevice(id: id, name: (d["name"] as? String) ?? "Device", category: (d["category"] as? String) ?? "",
                          productName: (d["product_name"] as? String) ?? (d["productName"] as? String) ?? "",
                          online: (d["online"] as? Bool) ?? ((d["online"] as? NSNumber)?.boolValue ?? true),
                          localKey: (d["local_key"] as? String) ?? (d["localKey"] as? String), statusCodes: codes.sorted())
    }

    private func has(_ c: String) -> Bool { ranges[c] != nil || statusCodes.contains(c) }
    private func first(_ codes: [String]) -> String? {
        codes.first { ranges[$0]?.isFunction == true } ?? codes.first(where: has)
    }

    var powerCode: String? { first(["switch_led", "switch_led_1", "led_switch", "switch_1", "switch"]) }
    var modeCode: String? { first(["work_mode", "work_mode_1"]) }
    var brightCode: String? { first(["bright_value_v2", "bright_value", "bright_value_1", "bright_value_2"]) }
    var tempCode: String? { first(["temp_value_v2", "temp_value", "temp_value_1"]) }
    var colourCode: String? { first(["colour_data_v2", "colour_data", "colour_data_hsv"]) }

    var isLight: Bool {
        !isPurifier && (Self.lightCategories.contains(category) || ["switch_led", "bright_value_v2", "bright_value", "colour_data_v2"].contains(where: has))
    }
    var isPurifier: Bool { category == "kj" }
    var isSwitch: Bool {
        !isLight && !isPurifier && category != "pc" && (Self.switchCategories.contains(category) || statusCodes.contains { $0 == "switch" || $0.hasPrefix("switch_") })
    }
    var supported: Bool { isLight || isSwitch || isPurifier }
    var kind: String {
        if isLight { return "Light" }
        if isPurifier { return "Air purifier" }
        switch category {
        case "cz": return "Plug"
        case "kg", "tdq", "kgq": return "Wall switch"
        default: return "Switch"
        }
    }

    var isV1: Bool {
        if let b = brightCode { return !b.hasSuffix("_v2") && (ranges[b]?.max ?? 1000) <= 255 }
        if let c = colourCode { return c == "colour_data" }
        return false
    }
    var brightRange: (Double, Double) {
        let lo = brightCode.flatMap { ranges[$0]?.min } ?? (isV1 ? 25 : 10)
        let hi = brightCode.flatMap { ranges[$0]?.max } ?? (isV1 ? 255 : 1000)
        return lo < hi ? (lo, hi) : (isV1 ? (25, 255) : (10, 1000))
    }
    var tempRange: (Double, Double) {
        let lo = tempCode.flatMap { ranges[$0]?.min } ?? 0
        let hi = tempCode.flatMap { ranges[$0]?.max } ?? (isV1 ? 255 : 1000)
        return lo < hi ? (lo, hi) : (0, isV1 ? 255 : 1000)
    }

    static let v2Map = ["20": "switch_led", "21": "work_mode", "22": "bright_value_v2", "23": "temp_value_v2", "24": "colour_data_v2"]
    static let v1Map = ["1": "switch_led", "2": "work_mode", "3": "bright_value", "4": "temp_value", "5": "colour_data"]

    /// Local data point id -> cloud code: from the cloud when it told us, else the standard layouts.
    func codeMap() -> [String: String] {
        if !dpMap.isEmpty || isPurifier { return dpMap }
        if isSwitch, let p = powerCode { return ["1": p] }   // plain switches put on/off on data point 1
        return brightCode == "bright_value_v2" || has("switch_led") && !has("bright_value") ? Self.v2Map : Self.v1Map
    }
    func dpID(for code: String) -> String? { codeMap().first { $0.value == code }?.key }

    var hasLocal: Bool { !(host ?? "").isEmpty && !(localKey ?? "").isEmpty }

    // MARK: Air purifier (same layout Exhale sends)

    private var purPower: String? { first(["switch", "switch_1", "power", "switch_power"]) }
    private var isAC3250: Bool { productName.uppercased().contains("AC3250") }

    /// The bridge's purifier entry, or nil if it can't go yet.
    func purifierEntry() -> [String: Any]? {
        guard isPurifier, hasLocal, let key = localKey, key.count == 16, let pc = purPower, let sw = dpID(for: pc) else { return nil }
        var o: [String: Any] = ["id": id, "name": name, "key": key, "ip": host ?? "", "ver": version ?? 3.3, "sw": sw]
        if let c = first(["pm25", "pm25_value", "pm2_5", "pm_25", "pm25_val"]), let dp = dpID(for: c) {
            o["pm"] = dp
            o["pmDiv"] = pow(10, Double(ranges[c]?.scale ?? 0))
        }
        if let m = first(["mode", "work_mode", "fan_mode", "manual_mode"]), let dp = dpID(for: m), let r = ranges[m]?.values,
           let auto = r.first(where: { ["auto", "smart"].contains($0.lowercased()) }),
           let manual = r.first(where: { $0.lowercased() == "manual" }) {
            o["mode"] = dp; o["modeAuto"] = auto; o["modeManual"] = manual
        }
        if isAC3250 {
            // GermGuardian AC3250: data point 4 is fan speed as text "1"..."10", 110 is the display (not in the cloud).
            o["fan"] = "4"; o["fanValues"] = (1...10).map { String($0) }
            o["display"] = "110"; o["displayInverted"] = false; o["keepDisplayOff"] = false
        } else if let f = first(["speed", "fan_speed_enum", "fan_speed", "fan_level"]), let dp = dpID(for: f) {
            if let vals = ranges[f]?.values, !vals.isEmpty { o["fan"] = dp; o["fanValues"] = vals }
            else if let lo = ranges[f]?.min, let hi = ranges[f]?.max, hi > lo, hi - lo <= 20 {
                o["fan"] = dp; o["fanValues"] = Array(Int(lo)...Int(hi))
            }
        }
        if let c = first(["lock", "child_lock"]), let dp = dpID(for: c) { o["lock"] = dp }
        if let c = first(["filter", "filter_life", "filter_days", "filter_left", "filter_life_percent"]), let dp = dpID(for: c) {
            o["filter"] = dp; o["filterMax"] = Int(ranges[c]?.max ?? 100)
        }
        return o
    }

    /// Why it can't go to the bridge, or nil.
    var problem: String? {
        if isPurifier, !(localKey ?? "").isEmpty, purPower.flatMap({ dpID(for: $0) }) == nil, !dpMap.isEmpty {
            return "Keystone can't find its power control."
        }
        if (localKey ?? "").isEmpty { return "Tuya gives no local key for it, so only the cloud can control it (common for Matter devices: add those to Apple Home with their Matter code)." }
        if !isPurifier, powerCode == nil || dpID(for: powerCode!) == nil { return "Keystone can't find its on/off control." }
        if (host ?? "").isEmpty {
            return isPurifier ? "Not heard on your Wi-Fi yet. Keep it on and powered; the bridge listens for it."
                : "Sent, but the bridge hasn't heard it announce itself on your Wi-Fi yet. It picks the address up on its own when it does. If it never does, the device doesn't speak Tuya's local protocol (Matter-only devices don't)."
        }
        return nil
    }

    /// The bridge's light entry (Afterglow's format), or nil if it can't go yet.
    func bridgeEntry() -> [String: Any]? {
        guard !isPurifier, !(localKey ?? "").isEmpty, let pc = powerCode, let sw = dpID(for: pc) else { return nil }
        var d: [String: Any] = ["id": id, "name": name, "key": localKey ?? "", "ip": host ?? "", "ver": version ?? 3.3, "sw": sw]
        if let c = modeCode, let dp = dpID(for: c) { d["mode"] = dp }
        if let c = brightCode, let dp = dpID(for: c) {
            d["bri"] = dp; d["briMin"] = Int(brightRange.0); d["briMax"] = Int(brightRange.1)
        }
        if let c = tempCode, let dp = dpID(for: c) {
            d["ct"] = dp; d["ctMin"] = Int(tempRange.0); d["ctMax"] = Int(tempRange.1)
        }
        if let c = colourCode, let dp = dpID(for: c) { d["col"] = dp; d["colV1"] = isV1 || c == "colour_data" }
        if d["bri"] == nil, d["ct"] == nil, d["col"] == nil, !isLight { d["kind"] = "switch" }
        return d
    }
}

/// The Smart Life devices Keystone knows, which of them are in Apple Home, and sending them to the bridge.
@MainActor
final class HomeDevices: ObservableObject {
    static let shared = HomeDevices()

    @Published var devices: [HomeDevice] = AppGroup.read([HomeDevice].self, "home-devices.json") ?? []
    @Published var busy: String?
    @Published var message: String?

    private func save() { AppGroup.write(devices, "home-devices.json") }

    /// Pulls the device list from Smart Life, keeping what Keystone already learned (addresses, choices).
    func refresh(_ token: TuyaToken) async {
        busy = "Reading your Smart Life devices…"
        defer { busy = nil }
        let client = TuyaClient(token: token)
        do {
            let fresh = try await client.allDevicesRaw().compactMap(HomeDevice.parse).filter(\.supported)
            var merged: [HomeDevice] = []
            for var d in fresh {
                if let old = devices.first(where: { $0.id == d.id }) {
                    d.host = old.host; d.version = old.version; d.inHome = old.inHome
                    d.ranges = old.ranges; d.dpMap = old.dpMap
                    if d.localKey == nil { d.localKey = old.localKey }
                    if d.localKey != old.localKey { d.version = nil }   // re-paired: the key changed
                }
                merged.append(d)
            }
            let need = merged.filter { $0.dpMap.isEmpty || $0.ranges.isEmpty }.map(\.id)
            let extra = await withTaskGroup(of: (String, [String: TuyaRange], [String: String]).self) { g in
                for id in need {
                    g.addTask {
                        let r = (try? await client.specRanges(id: id)) ?? [:]
                        let m = (try? await client.dpCodes(id: id)) ?? [:]
                        return (id, r, m)
                    }
                }
                var out: [String: ([String: TuyaRange], [String: String])] = [:]
                for await x in g { out[x.0] = (x.1, x.2) }
                return out
            }
            for i in merged.indices {
                if let e = extra[merged[i].id] {
                    if !e.0.isEmpty { merged[i].ranges = e.0 }
                    if !e.1.isEmpty { merged[i].dpMap = e.1 }
                }
            }
            devices = merged.sorted { ($0.isLight ? 0 : 1, $0.name) < ($1.isLight ? 0 : 1, $1.name) }
            save()
        } catch {
            message = error.localizedDescription
        }
    }

    /// Finds addresses on the Wi-Fi: known addresses first, then a scan of port 6668 matched by key.
    /// Addresses the bridge heard Tuya devices announce (firmware 1.11.1+): id -> (ip, protocol version).
    func bridgeHeard(_ link: BridgeLink, listen: Bool = false) async -> [String: (String, Double?)] {
        guard let (code, data) = try? await Transport.send(link, method: "GET", path: listen ? "/api/tuya/seen?listen=1" : "/api/tuya/seen",
                                                             headers: ["X-Device-Token": link.token], body: nil, timeout: 5),
              code == 200, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: (String, Double?)] = [:]
        for d in obj["devices"] as? [[String: Any]] ?? [] {
            if let id = d["id"] as? String, let ip = d["ip"] as? String { out[id] = (ip, (d["ver"] as? String).flatMap(Double.init)) }
        }
        return out
    }

    func find(_ ids: [String]? = nil, link: BridgeLink = .stored) async {
        let targets = devices.filter { (ids == nil || ids!.contains($0.id)) && !($0.localKey ?? "").isEmpty }
        guard !targets.isEmpty else { return }
        busy = "Asking the bridge which devices it has heard…"
        defer { busy = nil }
        var hits: [String: (String, Double)] = [:]
        var left = targets
        // The bridge hears every Tuya device announce its address; that's the reliable way.
        // 1.11.3+ listens in short windows: ask it to listen, give it time, then read what it heard.
        var heard = await bridgeHeard(link, listen: true)
        if targets.contains(where: { heard[$0.id] == nil }) {
            busy = "The bridge is listening for your devices (about 15 s)…"
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            heard.merge(await bridgeHeard(link)) { _, new in new }
        }
        for d in targets {
            if let h = heard[d.id] { hits[d.id] = (h.0, h.1 ?? d.version ?? 3.3); left.removeAll { $0.id == d.id } }
        }
        guard !left.isEmpty, LocalScan.wifiAddress() != nil else { apply(hits, targets: targets, left: left); return }
        busy = "Looking for devices on your Wi-Fi…"
        for d in targets {
            guard let h = d.host else { continue }
            if let v = await Self.probe(d, host: h, versions: d.version.map { [$0] } ?? [3.3, 3.4, 3.5]) {
                hits[d.id] = (h, v); left.removeAll { $0.id == d.id }
            }
        }
        if !left.isEmpty {
            let hosts = await LocalScan.openHosts { done in
                Task { @MainActor in HomeDevices.shared.busy = "Scanning Wi-Fi… \(Int(Double(done) / 253 * 100))%" }
            }
            let taken = Set(hits.values.map(\.0)).union(devices.compactMap(\.host).filter { h in !left.contains { $0.host == h } })
            let open = hosts.filter { !taken.contains($0) }
            busy = "Matching \(left.count) device\(left.count == 1 ? "" : "s") to \(open.count) address\(open.count == 1 ? "" : "es")…"
            let pool = Pool(left)
            await withTaskGroup(of: Void.self) { g in
                for host in open {
                    g.addTask {
                        for versions in [[3.4, 3.5], [3.3]] {
                            for d in await pool.remaining() {
                                if let v = await HomeDevices.probe(d, host: host, versions: versions) {
                                    await pool.matched(d.id, host, v); return
                                }
                            }
                        }
                    }
                }
            }
            for (id, h) in await pool.hits { hits[id] = h }
        }
        apply(hits, targets: targets, left: left)
    }

    private func apply(_ hits: [String: (String, Double)], targets: [HomeDevice], left: [HomeDevice]) {
        for i in devices.indices {
            if let h = hits[devices[i].id] { devices[i].host = h.0; devices[i].version = h.1 }
            else if left.contains(where: { $0.id == devices[i].id }) { devices[i].host = nil }   // not there any more
        }
        save()
    }

    nonisolated static func probe(_ d: HomeDevice, host: String, versions: [Double]) async -> Double? {
        guard let key = d.localKey else { return nil }
        guard let r = try? await LocalLink.detect(devId: d.id, host: host, localKey: key, knownDPs: Array(d.codeMap().keys),
                                                  timeout: 1.6, versions: versions, onDPS: { _ in }, onClose: { _ in }) else { return nil }
        let v = r.0.version, dps = r.1
        await r.0.close()
        return v >= 3.4 || !dps.isEmpty ? v : nil   // 3.4+ proves the key in the handshake; 3.3 needs real data
    }

    /// Turns a device's Apple Home tile on or off, then sends the list to the bridge.
    func setInHome(_ id: String, _ on: Bool, link: BridgeLink) async -> String {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return "" }
        devices[i].inHome = on
        if on && devices[i].isPurifier {   // the bridge has room for one purifier
            for j in devices.indices where j != i && devices[j].isPurifier { devices[j].inHome = false }
        }
        save()
        if on && !devices[i].hasLocal { await find([id], link: link) }
        let r: String
        if devices[i].isPurifier { r = await pushPurifier(link) } else { r = await push(link) }
        if on, let d = devices.first(where: { $0.id == id }), let why = d.problem {
            return "\(d.name) can't go to Apple Home yet: \(why)"
        }
        return r
    }

    /// Sends every chosen device that the bridge can reach. The bridge restarts if Home's list changes.
    @discardableResult
    func push(_ link: BridgeLink) async -> String {
        let entries = devices.filter(\.inHome).compactMap { $0.bridgeEntry() }
        do {
            let r = try await BridgeAPI.post("/api/ks/lights", ["lights": entries], link, timeout: 10)
            if (r["restart"] as? Bool) == true { return "Sent. The bridge is restarting to update Apple Home (about 20 s)." }
            return "Sent to the bridge."
        } catch {
            return "Couldn't send to the bridge (it needs firmware 1.11 or newer): \(error.localizedDescription)"
        }
    }
}

extension HomeDevices {
    /// Every light, switch and plug, plus the first purifier, into Apple Home in one go.
    func addAll(link: BridgeLink) async -> String {
        var purifierTaken = false
        for i in devices.indices where !(devices[i].localKey ?? "").isEmpty {
            if devices[i].isPurifier {
                devices[i].inHome = !purifierTaken
                purifierTaken = true
            } else {
                devices[i].inHome = true
            }
        }
        save()
        let missing = devices.filter { $0.inHome && !$0.hasLocal }.map(\.id)
        if !missing.isEmpty { await find(missing, link: link) }
        let a = await push(link)
        if purifierTaken { _ = await pushPurifier(link) }
        let sent = devices.filter { $0.inHome && $0.problem == nil }.count
        let stuck = devices.filter { $0.inHome && $0.problem != nil }.map(\.name)
        return stuck.isEmpty ? "\(sent) device\(sent == 1 ? "" : "s") sent. \(a)"
            : "\(sent) sent. Not on Wi-Fi or no local key: \(stuck.joined(separator: ", ")). \(a)"
    }

    /// Sends the chosen purifier, or removes it from Home when none is chosen (that also removes one Exhale sent).
    @discardableResult
    func pushPurifier(_ link: BridgeLink) async -> String {
        var body: [String: Any] = ["utcOffset": TimeZone.current.secondsFromGMT()]
        if let p = devices.first(where: { $0.isPurifier && $0.inHome }), let e = p.purifierEntry() { body["purifier"] = e }
        do {
            let r = try await BridgeAPI.post("/api/dev/config?app=exhale", body, link, timeout: 10)
            return (r["restart"] as? Bool) == true ? "Sent. The bridge is restarting to update Apple Home (about 20 s)." : "Sent to the bridge."
        } catch {
            return "Couldn't send to the bridge (it needs firmware 1.11 or newer): \(error.localizedDescription)"
        }
    }
}

private actor Pool {
    private var left: [HomeDevice]
    private(set) var hits: [String: (String, Double)] = [:]
    init(_ l: [HomeDevice]) { left = l }
    func remaining() -> [HomeDevice] { left }
    func matched(_ id: String, _ host: String, _ v: Double) {
        left.removeAll { $0.id == id }
        hits[id] = (host, v)
    }
}
