import WidgetKit
import SwiftUI
import AppIntents

private enum KeystoneWidgetStyle {
    static let yellow = Color(red: 1, green: 0.83, blue: 0.07)
    static let cyan = Color(red: 0.35, green: 0.80, blue: 0.98)
    static let muted = Color.white.opacity(0.62)
    static let background = LinearGradient(
        colors: [Color(red: 0.065, green: 0.09, blue: 0.14),
                 Color(red: 0.025, green: 0.035, blue: 0.065)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

private extension BridgeHealthEntry {
    var justChecked: Bool {
        verified && checkedAt.map { date.timeIntervalSince($0) >= 0 && date.timeIntervalSince($0) < 300 } == true
    }

    var updatedText: String {
        guard let checkedAt else { return "No bridge data" }
        return (justChecked ? "Checked " : "Last reading ") +
            checkedAt.formatted(date: .omitted, time: .shortened)
    }

    var freshTemperature: Double? {
        guard let g = info?.govee, g.source != "stale",
              g.heardAgo.map({ $0 <= 120 }) ?? (g.feedActive == true) else { return nil }
        return g.temp
    }

    var sensorSource: String {
        guard let g = info?.govee else { return "Not configured" }
        switch g.source {
        case "equinox": return "Equinox"
        case "dewpoint": return "DewPoint"
        case "localBLE": return "Bridge BLE"
        default: return "Sensor unavailable"
        }
    }
}

struct ClimateWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeystoneClimate", provider: BridgeHealthProvider()) { entry in
            ClimateWidgetView(entry: entry)
                .containerBackground(for: .widget) { KeystoneWidgetStyle.background }
        }
        .configurationDisplayName("AC & Climate")
        .description("Govee temperature and humidity, selected sensor, AC and Smart Auto.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct ClimateWidgetView: View {
    let entry: BridgeHealthEntry
    @Environment(\.widgetFamily) private var family

    private var f: Bool { entry.info?.display?.tempF ?? false }
    private var govee: BridgeInfo.Govee? { entry.info?.govee }
    private var ac: BridgeInfo.AC? { entry.info?.ac }
    private var reading: String { Fmt.temp(entry.freshTemperature, f: f) }
    private var humidity: String {
        guard entry.freshTemperature != nil, let value = govee?.humidity else { return "—" }
        return "\(Int(value.rounded()))%"
    }
    private var acStatus: String {
        guard let ac, ac.configured == true else { return "AC not configured" }
        if ac.on == false { return "AC off" }
        if ac.auto?.enabled == true { return "AC Smart Auto" }
        return ["Fan", "Heat", "Cool", "Dry", "Auto"][min(4, max(0, ac.mode ?? 2))]
    }
    private var setpoint: String {
        guard let a = ac else { return "—" }
        let c: Double? = a.auto?.enabled == true ? a.auto?.setpoint :
            a.target.map { a.fahrenheit == true ? (Double($0) - 32) * 5 / 9 : Double($0) }
        return Fmt.temp(c, f: f)
    }
    private var canControl: Bool {
        entry.justChecked && ac?.configured == true && ac?.ok == true && ac?.on != nil
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Room · \(entry.sensorSource)", systemImage: "thermometer.medium")
                        .font(.caption2)
                    Text("\(reading)  \(humidity)").font(.headline)
                    Text(acStatus).font(.caption2).lineLimit(1)
                }
            case .systemMedium, .systemLarge:
                expanded
            default:
                compact
            }
        }
    }

    private var heading: some View {
        HStack {
            Label("AC & CLIMATE", systemImage: "thermometer.medium")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(KeystoneWidgetStyle.yellow)
            Spacer()
            Text(entry.justChecked ? "Recently checked" : "Cached")
                .font(.system(size: 10)).foregroundStyle(KeystoneWidgetStyle.muted)
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 5) {
            heading
            Spacer(minLength: 0)
            Text(reading).font(.system(size: 34, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6).lineLimit(1)
            Text("Humidity \(humidity)").font(.caption).foregroundStyle(KeystoneWidgetStyle.cyan)
            Text(acStatus).font(.caption.weight(.semibold)).lineLimit(1)
            Text(entry.updatedText).font(.system(size: 9)).foregroundStyle(KeystoneWidgetStyle.muted)
        }
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading
            HStack(alignment: .center, spacing: 13) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading).font(.system(size: 32, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("Humidity \(humidity)").font(.caption).foregroundStyle(KeystoneWidgetStyle.cyan)
                    Text(entry.sensorSource).font(.caption2).foregroundStyle(KeystoneWidgetStyle.muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(acStatus).font(.caption.weight(.semibold)).lineLimit(1)
                    Text("Target \(setpoint)").font(.subheadline)
                    if canControl, let on = ac?.on {
                        Button(intent: SetACPowerIntent(on: !on)) {
                            Label(on ? "Turn AC off" : "Turn AC on",
                                  systemImage: "power")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(KeystoneWidgetStyle.yellow)
                    } else {
                        Text("Open Keystone for controls")
                            .font(.caption2).foregroundStyle(KeystoneWidgetStyle.muted)
                    }
                }
            }
            if family == .systemLarge {
                Divider()
                Text("Smart Auto: \(ac?.auto?.enabled == true ? "Active" : "Inactive")")
                    .font(.caption)
                if let b = ac?.auto?.band {
                    Text(String(format: "Smart Auto range: ±%.1f°C", b)).font(.caption)
                }
                if let battery = govee?.battery {
                    Text("Govee battery \(battery)%").font(.caption)
                }
                Spacer(minLength: 0)
            }
            Text(entry.updatedText).font(.caption2).foregroundStyle(KeystoneWidgetStyle.muted)
        }
    }
}

struct PowerStripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeystonePowerStrip", provider: BridgeHealthProvider()) { entry in
            PowerStripWidgetView(entry: entry)
                .containerBackground(for: .widget) { KeystoneWidgetStyle.background }
        }
        .configurationDisplayName("Power Strip")
        .description("Verified local strip outlets. Cloud-only Tuya devices are not silently treated as LAN devices.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PowerStripWidgetView: View {
    let entry: BridgeHealthEntry
    @Environment(\.widgetFamily) private var family

    private var strip: BridgeInfo.Strip? { entry.info?.strip }
    private var outlets: [BridgeInfo.Strip.Outlet] { strip?.outlets ?? [] }
    private var usable: Bool {
        entry.justChecked && strip?.configured == true && strip?.ok == true &&
        strip?.known == true && strip?.id?.isEmpty == false && strip?.ip?.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("POWER STRIP", systemImage: "poweroutlet.strip")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(KeystoneWidgetStyle.yellow)
                Spacer()
                Text(usable ? "LAN verified" : "Not verified")
                    .font(.system(size: 10)).foregroundStyle(KeystoneWidgetStyle.muted)
            }
            if strip?.configured != true {
                Spacer()
                Text("No local strip configured").font(.caption)
                Text("Set up in Keystone or use Tuya cloud control.")
                    .font(.caption2).foregroundStyle(KeystoneWidgetStyle.muted)
                Spacer()
            } else if outlets.isEmpty {
                Spacer()
                Text("No individual outlets").font(.caption)
                Spacer()
            } else {
                ForEach(Array(outlets.prefix(family == .systemSmall ? 2 :
                                             family == .systemMedium ? 3 : 6).enumerated()),
                        id: \.offset) { index, outlet in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(outlet.on == true && usable ? KeystoneWidgetStyle.yellow :
                                  Color.white.opacity(0.3)).frame(width: 6, height: 6)
                        Text(outlet.name).font(.caption).lineLimit(1)
                        Spacer(minLength: 2)
                        if usable, let on = outlet.on, let id = strip?.id {
                            Button(intent: SetStripOutletIntent(outlet: index, stripID: id, on: !on)) {
                                Text(on ? "Off" : "On")
                                    .font(.caption.weight(.semibold)).frame(minWidth: 25)
                            }
                            .buttonStyle(.bordered)
                            .tint(KeystoneWidgetStyle.yellow)
                        } else {
                            Text(outlet.on.map { $0 ? "On" : "Off" } ?? "Unknown")
                                .font(.caption2).foregroundStyle(KeystoneWidgetStyle.muted)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            Text(entry.updatedText).font(.system(size: 9))
                .foregroundStyle(KeystoneWidgetStyle.muted).lineLimit(1)
        }
        .widgetURL(nil)
    }
}

// Configurable dashboard: choose two genuinely different metrics from one
// shared bridge snapshot. Widgets do not execute firmware resets or OTA.
enum OverviewPanel: String, AppEnum {
    case health, climate, strip, airQuality, tv, relay

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Bridge metric"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .health: "Bridge RAM and uptime",
        .climate: "Climate and AC",
        .strip: "Power strip",
        .airQuality: "Air quality",
        .tv: "TV",
        .relay: "Remote relay"
    ]
}

struct OverviewConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configure Keystone Overview"
    static var description = IntentDescription("Choose which two bridge metrics appear.")

    @Parameter(title: "First metric") var first: OverviewPanel
    @Parameter(title: "Second metric") var second: OverviewPanel

    init() { first = .health; second = .climate }
}

struct OverviewProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> BridgeHealthEntry { .preview }

    func snapshot(for configuration: OverviewConfiguration, in context: Context) async -> BridgeHealthEntry {
        if context.isPreview { return .preview }
        let saved = Snapshot.stored
        return BridgeHealthEntry(date: .now, info: saved?.info,
                                 checkedAt: saved?.at, verified: false)
    }

    func timeline(for configuration: OverviewConfiguration, in context: Context) async -> Timeline<BridgeHealthEntry> {
        let now = Date()
        let link = BridgeLink.stored
        if link.isSet, let info = try? await BridgeAPI.info(link, timeout: 4, lite: true) {
            Snapshot.stored = Snapshot(info: info, at: now)
            let fresh = BridgeHealthEntry(date: now, info: info, checkedAt: now, verified: true)
            let aging = BridgeHealthEntry(date: now.addingTimeInterval(300),
                                          info: info, checkedAt: now, verified: false)
            return Timeline(entries: [fresh, aging],
                            policy: .after(now.addingTimeInterval(15 * 60)))
        }
        let saved = Snapshot.stored
        return Timeline(entries: [
            BridgeHealthEntry(date: now, info: saved?.info, checkedAt: saved?.at, verified: false)
        ], policy: .after(now.addingTimeInterval(15 * 60)))
    }
}

struct KeystoneOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "KeystoneOverview",
                               intent: OverviewConfiguration.self,
                               provider: OverviewProvider()) { entry, configuration in
            KeystoneOverviewView(entry: entry, configuration: configuration)
                .containerBackground(for: .widget) { KeystoneWidgetStyle.background }
        }
        .configurationDisplayName("Keystone Overview")
        .description("Choose two metrics: health, AC, strip, air quality, TV, or relay.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct KeystoneOverviewView: View {
    let entry: BridgeHealthEntry
    let configuration: OverviewConfiguration
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("KEYSTONE OVERVIEW", systemImage: "square.grid.2x2")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(KeystoneWidgetStyle.yellow)
                Spacer()
                Text(entry.justChecked ? "Recently checked" : "Cached")
                    .font(.caption2).foregroundStyle(KeystoneWidgetStyle.muted)
            }
            if family == .systemLarge {
                panel(configuration.first)
                Divider()
                panel(configuration.second)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    panel(configuration.first)
                    Divider()
                    panel(configuration.second)
                }
            }
            Spacer(minLength: 0)
            Text(entry.updatedText).font(.system(size: 10))
                .foregroundStyle(KeystoneWidgetStyle.muted)
        }
        .widgetURL(URL(string: "keystone://health"))
    }

    private func panel(_ value: OverviewPanel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value.title).font(.caption2.weight(.semibold))
                .foregroundStyle(KeystoneWidgetStyle.cyan)
            Text(metric(value)).font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.62)
            Text(detail(value)).font(.caption).foregroundStyle(KeystoneWidgetStyle.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ panel: OverviewPanel) -> String {
        switch panel {
        case .health: return entry.info?.heap.map { "\($0 / 1024) KB" } ?? "—"
        case .climate: return Fmt.temp(entry.freshTemperature, f: entry.info?.display?.tempF ?? false)
        case .strip:
            guard let outlets = entry.info?.strip?.outlets,
                  entry.info?.strip?.known == true else { return "—" }
            return "\(outlets.filter { $0.on == true }.count)/\(outlets.count) on"
        case .airQuality: return entry.info?.purifier?.pm25.map { "\(Int($0.rounded())) PM2.5" } ?? "—"
        case .tv: return entry.info?.tv?.state ?? "—"
        case .relay:
            guard let r = entry.info?.remote else { return "—" }
            return r.on == false ? "Off" : r.connected == true ? "Connected" : "Unavailable"
        }
    }

    private func detail(_ panel: OverviewPanel) -> String {
        switch panel {
        case .health: return "Up \(Fmt.uptime(entry.info?.uptime)) · block \(entry.info?.heapBlock.map { "\($0 / 1024) KB" } ?? "—")"
        case .climate: return "\(entry.sensorSource) · \(entry.info?.ac?.auto?.enabled == true ? "Smart Auto" : "AC manual/off")"
        case .strip:
            return entry.info?.strip?.ok == true ? "LAN strip responding" : "Local control unavailable"
        case .airQuality: return Fmt.aq(entry.info?.purifier?.pm25)
        case .tv: return "TV status from bridge"
        case .relay: return entry.info?.remote?.broker ?? "MQTT relay"
        }
    }
}

private extension OverviewPanel {
    var title: String {
        switch self {
        case .health: return "FREE RAM"
        case .climate: return "ROOM"
        case .strip: return "POWER STRIP"
        case .airQuality: return "AIR"
        case .tv: return "TV"
        case .relay: return "REMOTE"
        }
    }
}
