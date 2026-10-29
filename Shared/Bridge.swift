import Foundation

/// Where the bridge is and Keystone's token for it. Lives in the App Group so the widget can read it.
struct BridgeLink: Codable, Equatable {
    var host = ""
    var port = 8080
    var token = ""

    var isSet: Bool { !host.isEmpty && !token.isEmpty }

    static var stored: BridgeLink {
        get { AppGroup.read(BridgeLink.self, "link.json") ?? BridgeLink() }
        set { AppGroup.write(newValue, "link.json") }
    }
}

/// Everything /api/info reports. All optional: older firmware leaves things out.
struct BridgeInfo: Codable, Equatable {
    struct Light: Codable, Equatable, Identifiable { var id: String; var name: String; var on: Bool?; var bri: Int?; var ok: Bool? }
    struct TV: Codable, Equatable { var state: String?; var host: String? }
    struct Purifier: Codable, Equatable {
        var paired: Bool?; var configured: Bool?; var name: String?; var ok: Bool?; var on: Bool?; var auto: Bool?
        var pm25: Double?; var speed: Int?; var display: Bool?; var keepDisplayOff: Bool?
    }
    struct IR: Codable, Equatable { struct R: Codable, Equatable { var name: String; var buttons: Int?; var power: Bool?; var names: [String]? }; var paired: Bool?; var remotes: [R]? }
    struct Govee: Codable, Equatable { var locked: Bool?; var name: String?; var temp: Double?; var humidity: Double?; var battery: Int?; var heardAgo: Int? }
    struct TVTile: Codable, Equatable { var inHome: Bool?; var inputs: [String]? }
    struct Bar: Codable, Equatable { var claimed: Bool?; var configured: Bool?; var state: String?; var follow: Bool?; var events: [String]? }
    struct Paired: Codable, Equatable { var afterglow: Bool?; var subwave: Bool?; var exhale: Bool?; var redshift: Bool?; var equinox: Bool?; var nightjar: Bool? }
    struct Camera: Codable, Equatable {
        struct Rule: Codable, Equatable { var enabled: Bool?; var window: Bool?; var from: Int?; var to: Int?; var offAfter: Int?; var lights: [String]?; var offIn: Int? }
        var paired: Bool?; var configured: Bool?; var name: String?; var ok: Bool?; var error: String?
        var online: Bool?; var charging: Bool?; var battery: Int?; var motion: Bool?; var person: Bool?
        var lastEventAgo: Int?; var lastType: String?; var rule: Rule?
    }
    struct AC: Codable, Equatable {
        struct Auto: Codable, Equatable { var enabled: Bool?; var setpoint: Double?; var band: Double?; var lastSwitchAgo: Int? }
        var configured: Bool?; var name: String?; var ok: Bool?; var error: String?; var on: Bool?; var mode: Int?
        var target: Int?; var fahrenheit: Bool?; var indoor: Double?; var room: Double?; var auto: Auto?
    }

    var app: String
    var version: String?
    var build: Int?
    var chip: String?
    var name: String?
    var ip: String?
    var rssi: Int?
    var ssid: String?
    var heap: Int?
    var uptime: Int?
    var time: String?
    var lights: [Light]?
    var events: [String]?
    var tv: TV?
    var learnedDelay: Int?
    var samples: Int?
    var followTV: Bool?
    var barFollow: Bool?
    var countdown: Int?
    var purifier: Purifier?
    var ir: IR?
    var govee: Govee?
    var tvTile: TVTile?
    var bar: Bar?
    var display: DisplaySettings?
    var paired: Paired?
    var keystone: Bool?
    var claimed: Bool?
    var ac: AC?
    var camera: Camera?
    var remote: Remote?
    var boot: Boot?
    var heapBlock: Int?
    struct Boot: Codable, Equatable { var reason: String?; var crashes: Int?; var safeMode: Bool?; var minHeap: Int? }
    struct Remote: Codable, Equatable { var on: Bool?; var connected: Bool?; var served: Int?; var error: String?; var id: String?
        var heard: Int?; var badKey: Int?; var stale: Int?; var tooBig: Int? }
    var auth: Bool?

    var displayName: String { name ?? "Keystone Bridge" }
    var lightsOn: Int { (lights ?? []).filter { $0.on == true }.count }
    var tvIsOn: Bool { tv?.state == "on" }
    var supportsKeystone: Bool { display != nil }
}

struct DisplaySettings: Codable, Equatable {
    var bright: Int = 160
    var flip: Bool = false
    var cycle: Int = 6
    var pages: Int = 31
    var clock24: Bool = true
    var tempF: Bool = false
    var nightOn: Bool = false
    var nightFrom: Int = 23 * 60
    var nightTo: Int = 7 * 60
    var nightMode: Int = 1
    var countdownWakes: Bool = true
    var on: Bool = true
    var present: Bool? = nil

    enum Page: Int, CaseIterable, Identifiable {
        case clock = 1, room = 2, air = 4, lights = 8, tv = 16
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .clock: return "Clock"
            case .room: return "Room temperature (Govee)"
            case .air: return "Air quality (PM2.5)"
            case .lights: return "Lights on"
            case .tv: return "TV"
            }
        }
        var icon: String {
            switch self {
            case .clock: return "clock"
            case .room: return "thermometer.medium"
            case .air: return "aqi.medium"
            case .lights: return "lightbulb"
            case .tv: return "tv"
            }
        }
    }

    func has(_ p: Page) -> Bool { pages & p.rawValue != 0 }
    mutating func set(_ p: Page, _ on: Bool) { pages = on ? (pages | p.rawValue) : (pages & ~p.rawValue) }
}

enum BridgeError: LocalizedError {
    case message(String)
    case alreadyPaired
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .alreadyPaired: return "The bridge still remembers an older Keystone pairing."
        }
    }
}

enum BridgeAPI {
    static func url(_ host: String, _ port: Int, _ path: String) -> URL? { URL(string: "http://\(host):\(port)\(path)") }

    static func info(host: String, port: Int, timeout: Double = 4) async throws -> BridgeInfo {
        guard let u = url(host, port, "/api/info") else { throw BridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeout
        let (data, _) = try await URLSession.shared.data(for: req)
        let info = try JSONDecoder().decode(BridgeInfo.self, from: data)
        guard info.app == "afterglow-bridge" else { throw BridgeError.message("That isn't a Keystone bridge.") }
        return info
    }

    /// LAN when home, the encrypted relay when not.
    static func info(_ link: BridgeLink = .stored, timeout: Double = 4) async throws -> BridgeInfo {
        let (_, data) = try await Transport.send(link, method: "GET", path: "/api/info",
                                                 headers: ["X-Device-Token": link.token], timeout: timeout)
        let info = try JSONDecoder().decode(BridgeInfo.self, from: data)
        guard info.app == "afterglow-bridge" else { throw BridgeError.message("That isn't a Keystone bridge.") }
        return info
    }

    /// The relay details. The bridge only hands them out over the home network.
    static func relayConfig(_ link: BridgeLink = .stored) async throws -> RelayConfig? {
        guard let u = url(link.host, link.port, "/api/remote") else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 4
        req.setValue(link.token, forHTTPHeaderField: "X-Device-Token")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let b = o["broker"] as? String, let id = o["id"] as? String, let k = o["key"] as? String else { return nil }
        return RelayConfig(broker: b, id: id, key: k, on: (o["on"] as? Bool) ?? true)
    }

    /// Remote access on/off or a new key. LAN only, like the key itself.
    static func setRelay(_ body: [String: Any], _ link: BridgeLink = .stored) async throws -> RelayConfig? {
        guard let u = url(link.host, link.port, "/api/remote") else { return nil }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(link.token, forHTTPHeaderField: "X-Device-Token")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let b = o["broker"] as? String, let id = o["id"] as? String, let k = o["key"] as? String else {
            throw BridgeError.message("Remote access settings can only be changed on your home Wi-Fi.")
        }
        return RelayConfig(broker: b, id: id, key: k, on: (o["on"] as? Bool) ?? true)
    }

    static func claim(host: String, port: Int) async throws -> String {
        guard let u = url(host, port, "/api/dev/claim?app=keystone") else { throw BridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 409 { throw BridgeError.alreadyPaired }
        if code == 400 { throw BridgeError.message("This bridge firmware is too old for Keystone. Update it once from Afterglow (Settings › Apple Home bridge › Firmware), then pair here.") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let t = obj["token"] as? String else {
            throw BridgeError.message("The bridge didn't hand out a token.")
        }
        return t
    }

    /// The owner slot older firmware gives to Afterglow. Keystone borrows it only to update an old bridge.
    static func claimOwner(host: String, port: Int) async throws -> String {
        guard let u = url(host, port, "/api/claim") else { throw BridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 409 {
            throw BridgeError.message("Afterglow is already paired with this bridge, so the update has to come from there: Afterglow › Settings › Apple Home bridge › Firmware › Update. Then pair here.")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let t = obj["token"] as? String else {
            throw BridgeError.message("The bridge didn't answer the claim.")
        }
        return t
    }

    /// Clears a stale Keystone pairing using the owner (Afterglow) token.
    static func resetKeystone(host: String, port: Int, ownerToken: String) async throws {
        guard let u = url(host, port, "/api/dev/reset?app=keystone") else { throw BridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue(ownerToken, forHTTPHeaderField: "X-Afterglow-Token")
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw BridgeError.message("The bridge wouldn't clear the old pairing.") }
    }

    @discardableResult
    static func post(_ path: String, _ body: [String: Any] = [:], _ link: BridgeLink = .stored, timeout: Double = 6) async throws -> [String: Any] {
        let (code, data) = try await Transport.send(link, method: "POST", path: path,
                                                    headers: ["X-Device-Token": link.token],
                                                    body: try JSONSerialization.data(withJSONObject: body), timeout: timeout)
        if code == 401 { throw BridgeError.message("The bridge doesn't recognise this phone anymore. Forget it in Keystone and pair again.") }
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard code == 200 else { throw BridgeError.message((obj["error"] as? String) ?? "Bridge said HTTP \(code).") }
        return obj
    }

    static func setDisplay(_ d: DisplaySettings, _ link: BridgeLink = .stored) async throws {
        var dict = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any]) ?? [:]
        dict["present"] = nil
        try await post("/api/display", dict, link)
    }

    static func admin(_ action: String, _ extra: [String: Any] = [:], _ link: BridgeLink = .stored) async throws -> Bool {
        var body = extra
        body["action"] = action
        let r = try await post("/api/admin", body, link)
        return r["restart"] as? Bool ?? false
    }
}

/// What the widget shows, cached so it has something when the bridge can't be reached (away from home).
struct Snapshot: Codable, Equatable {
    var info: BridgeInfo
    var at: Date

    static var stored: Snapshot? {
        get { AppGroup.read(Snapshot.self, "snapshot.json") }
        set { if let v = newValue { AppGroup.write(v, "snapshot.json") } }
    }
}

enum Fmt {
    static func temp(_ c: Double?, f: Bool) -> String {
        guard let c else { return "–" }
        return String(format: "%.1f°", f ? c * 9 / 5 + 32 : c)
    }

    static func uptime(_ s: Int?) -> String {
        guard let s else { return "–" }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func signal(_ rssi: Int?) -> (bars: Int, text: String) {
        guard let r = rssi, r != 0 else { return (0, "–") }
        let bars = r > -55 ? 4 : r > -65 ? 3 : r > -75 ? 2 : 1
        return (bars, "\(r) dBm")
    }

    static func aq(_ pm: Double?) -> String {
        guard let pm else { return "–" }
        if pm <= 9 { return "Good" }
        if pm <= 35.4 { return "Moderate" }
        if pm <= 55.4 { return "Unhealthy for sensitive" }
        if pm <= 125.4 { return "Unhealthy" }
        return "Very unhealthy"
    }
}
