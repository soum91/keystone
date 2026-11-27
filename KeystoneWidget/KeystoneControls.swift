import Foundation
import AppIntents
import WidgetKit

// Interactive widgets run in the extension. Authenticate every command using
// Keystone's existing paired device token. Only send commands whose endpoints
// and current target can be verified, never guess outlet indexes from names.
struct SetACPowerIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Keystone AC Power"
    static var description = IntentDescription("Switch the currently paired Keystone AC on or off.")

    @Parameter(title: "On") var on: Bool

    init() {}
    init(on: Bool) { self.on = on }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let link = BridgeLink.stored
        guard link.isSet else { throw BridgeError.message("Pair Keystone in the app first.") }
        let current = try await BridgeAPI.info(link, timeout: 8, lite: true)
        guard current.auth == true, current.ac?.configured == true else {
            throw BridgeError.message("The paired bridge has no configured AC.")
        }
        _ = try await BridgeAPI.post("/api/control",
                                     ["device": "ac", "on": on], link, timeout: 9)
        WidgetCenter.shared.reloadTimelines(ofKind: "KeystoneClimate")
        WidgetCenter.shared.reloadTimelines(ofKind: "KeystoneOverview")
        return .result(dialog: IntentDialog(stringLiteral: "AC command queued; state will update when the bridge confirms it."))
    }
}

struct SetStripOutletIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Keystone Strip Outlet"
    static var description = IntentDescription("Switch one verified outlet of the configured local power strip.")

    @Parameter(title: "Outlet number") var outlet: Int
    @Parameter(title: "Strip ID") var stripID: String
    @Parameter(title: "On") var on: Bool

    init() {}
    init(outlet: Int, stripID: String, on: Bool) {
        self.outlet = outlet
        self.stripID = stripID
        self.on = on
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let link = BridgeLink.stored
        guard link.isSet else { throw BridgeError.message("Pair Keystone in the app first.") }
        let current = try await BridgeAPI.info(link, timeout: 8, lite: true)
        guard current.auth == true, let strip = current.strip,
              strip.configured == true, strip.id == stripID,
              strip.ok == true, strip.known == true,
              !(strip.ip ?? "").isEmpty,
              let outlets = strip.outlets,
              outlet >= 0, outlet < outlets.count,
              outlets[outlet].on != nil else {
            throw BridgeError.message("The strip isn't currently verified over LAN. Cloud-only devices must use Tuya/Surge instead.")
        }
        _ = try await BridgeAPI.post("/api/control",
                                     ["device": "strip", "outlet": outlet, "on": on],
                                     link, timeout: 9)
        WidgetCenter.shared.reloadTimelines(ofKind: "KeystonePowerStrip")
        WidgetCenter.shared.reloadTimelines(ofKind: "KeystoneOverview")
        return .result(dialog: IntentDialog(stringLiteral: "Outlet command queued; confirmation will follow the next bridge reading."))
    }
}
