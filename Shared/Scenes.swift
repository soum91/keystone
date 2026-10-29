import Foundation

/// A scene: a set of device states sent to the bridge in one go (at home or through the relay).
struct KScene: Codable, Identifiable, Hashable {
    struct Action: Codable, Hashable, Identifiable {
        var id = UUID()
        var label: String            // shown in the editor, e.g. "Ceiling light 40%"
        var device: String           // light, tv, bar, purifier, ac
        var idx: Int?
        var on: Bool?
        var bri: Int?
        var mode: String?
        var target: Double?
        var auto: Bool?
        var speed: Int?

        var body: [String: Any] {
            var b: [String: Any] = ["device": device]
            if let idx { b["idx"] = idx }
            if let on { b["on"] = on }
            if let bri { b["bri"] = bri }
            if let mode { b["mode"] = mode }
            if let target { b["target"] = target }
            if let auto { b["auto"] = auto }
            if let speed { b["speed"] = speed }
            return b
        }
    }

    var id = UUID()
    var name: String
    var icon: String
    var actions: [Action]

    static var stored: [KScene] {
        get { AppGroup.read([KScene].self, "scenes.json") ?? [] }
        set { AppGroup.write(newValue, "scenes.json") }
    }

    /// Sends every action. Returns the ones that failed (by label).
    @discardableResult
    static func run(_ s: KScene, link: BridgeLink = .stored) async -> [String] {
        var failed: [String] = []
        for a in s.actions {
            do { try await BridgeAPI.post("/api/control", a.body, link, timeout: 8) }
            catch { failed.append(a.label) }
        }
        return failed
    }

    /// Everything the bridge controls, as it is right now: the starting point for a new scene.
    static func capture(_ i: BridgeInfo) -> [Action] {
        var out: [Action] = []
        for (n, l) in (i.lights ?? []).enumerated() {
            let on = l.on == true
            out.append(Action(label: on ? "\(l.name) \(l.bri ?? 100)%" : "\(l.name) off", device: "light", idx: n,
                              on: on, bri: on ? l.bri : nil))
        }
        if i.tv?.host?.isEmpty == false {
            out.append(Action(label: "TV \(i.tvIsOn ? "on" : "off")", device: "tv", on: i.tvIsOn))
        }
        if i.bar?.configured == true {
            let on = i.bar?.state?.hasPrefix("on") == true
            out.append(Action(label: "Sound bar \(on ? "on" : "off")", device: "bar", on: on))
        }
        if let p = i.purifier, p.configured == true {
            if p.on == true {
                if p.auto == true { out.append(Action(label: "Purifier on, auto", device: "purifier", on: true, auto: true)) }
                else { out.append(Action(label: "Purifier fan \(p.speed ?? 1)", device: "purifier", on: true, speed: p.speed ?? 1)) }
            } else {
                out.append(Action(label: "Purifier off", device: "purifier", on: false))
            }
        }
        if let a = i.ac, a.configured == true {
            if a.on == true {
                if a.auto?.enabled == true {
                    out.append(Action(label: String(format: "AC Smart %.1f°", a.auto?.setpoint ?? 23), device: "ac",
                                      mode: "smart", target: a.auto?.setpoint))
                } else {
                    let f = a.fahrenheit == true
                    let c = a.target.map { f ? (Double($0) - 32) * 5 / 9 : Double($0) }
                    let m = ["fan", "heat", "cool", "dry", "auto"][min(4, max(0, a.mode ?? 2))]
                    out.append(Action(label: "AC \(m)\(c.map { String(format: " %.1f°", $0) } ?? "")", device: "ac",
                                      on: true, mode: m, target: c))
                }
            } else {
                out.append(Action(label: "AC off", device: "ac", on: false))
            }
        }
        return out
    }

    /// A first set of scenes, built from what this bridge actually has.
    static func starters(_ i: BridgeInfo) -> [KScene] {
        let lights = (i.lights ?? []).enumerated()
        let tv = i.tv?.host?.isEmpty == false
        let bar = i.bar?.configured == true
        var allOff: [Action] = lights.map { Action(label: "\($1.name) off", device: "light", idx: $0, on: false) }
        if tv { allOff.append(Action(label: "TV off", device: "tv", on: false)) }
        if bar { allOff.append(Action(label: "Sound bar off", device: "bar", on: false)) }
        var movie: [Action] = lights.map { Action(label: "\($1.name) 15%", device: "light", idx: $0, on: true, bri: 15) }
        if tv { movie.append(Action(label: "TV on", device: "tv", on: true)) }
        if bar { movie.append(Action(label: "Sound bar on", device: "bar", on: true)) }
        var bed = allOff
        if i.ac?.configured == true {
            bed.append(Action(label: String(format: "AC Smart %.1f°", i.ac?.auto?.setpoint ?? 22), device: "ac",
                              mode: "smart", target: i.ac?.auto?.setpoint ?? 22))
        }
        if i.purifier?.configured == true { bed.append(Action(label: "Purifier on, auto", device: "purifier", on: true, auto: true)) }
        return [
            KScene(name: "All off", icon: "power", actions: allOff),
            KScene(name: "Movie", icon: "film", actions: movie),
            KScene(name: "Bedtime", icon: "moon.stars", actions: bed),
        ].filter { !$0.actions.isEmpty }
    }
}
