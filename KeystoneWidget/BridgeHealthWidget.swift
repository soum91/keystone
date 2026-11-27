import WidgetKit
import SwiftUI

/// Bridge Health uses the firmware's /api/info telemetry. There is deliberately
/// no invented "health percentage": memory, boot, HomeKit and relay data are
/// measured by the bridge and may become stale when it cannot be contacted.
struct BridgeHealthEntry: TimelineEntry {
    let date: Date
    let info: BridgeInfo?
    let checkedAt: Date?
    let verified: Bool

    static let preview: BridgeHealthEntry = {
        let json = #"""
        {"app":"afterglow-bridge","name":"Keystone Bridge","version":"1.11.13",
         "build":188,"heap":55296,"heapBlock":38912,"uptime":226080,
         "rssi":-53,"homekit":{"connected":true,"status":"Connected","wifiDrops":1,"wifiReconnects":1},
         "remote":{"on":true,"connected":true,"broker":"EMQX","heard":25,"served":24},
         "boot":{"reason":"power on","crashes":0,"safeMode":false,"minHeap":41984},
         "govee":{"source":"equinox","feedActive":true,"feedAge":18}}
        """#
        let info = try? JSONDecoder().decode(BridgeInfo.self, from: Data(json.utf8))
        return BridgeHealthEntry(date: .now, info: info, checkedAt: .now, verified: true)
    }()
}

struct BridgeHealthProvider: TimelineProvider {
    func placeholder(in context: Context) -> BridgeHealthEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (BridgeHealthEntry) -> Void) {
        if context.isPreview {
            completion(.preview)
            return
        }
        let cached = Snapshot.stored
        // A file from an earlier app session is useful but not proof of reachability.
        completion(BridgeHealthEntry(date: .now, info: cached?.info, checkedAt: cached?.at, verified: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BridgeHealthEntry>) -> Void) {
        Task {
            let now = Date()
            let link = BridgeLink.stored
            if link.isSet, let info = try? await BridgeAPI.info(link, timeout: 4, lite: true) {
                Snapshot.stored = Snapshot(info: info, at: now)
                // Never leave a success indication on-screen indefinitely if
                // WidgetKit delays the next network refresh.
                let fresh = BridgeHealthEntry(date: now, info: info, checkedAt: now, verified: true)
                let aging = BridgeHealthEntry(date: now.addingTimeInterval(5 * 60),
                                              info: info, checkedAt: now, verified: false)
                completion(Timeline(entries: [fresh, aging],
                                    policy: .after(now.addingTimeInterval(15 * 60))))
            } else {
                let cached = Snapshot.stored
                let failed = BridgeHealthEntry(date: now, info: cached?.info,
                                              checkedAt: cached?.at, verified: false)
                completion(Timeline(entries: [failed],
                                    policy: .after(now.addingTimeInterval(15 * 60))))
            }
        }
    }
}

struct BridgeHealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeystoneBridgeHealth", provider: BridgeHealthProvider()) { entry in
            BridgeHealthView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.07, green: 0.10, blue: 0.14),
                                            Color(red: 0.025, green: 0.035, blue: 0.055)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
        }
        .configurationDisplayName("Bridge Health")
        .description("Last verified bridge connection, RAM, uptime, HomeKit, relay and Govee feed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct BridgeHealthView: View {
    let entry: BridgeHealthEntry
    @Environment(\.widgetFamily) private var family

    private let yellow = Color(red: 1, green: 0.83, blue: 0.08)
    private let cyan = Color(red: 0.35, green: 0.80, blue: 0.98)
    private let green = Color(red: 0.29, green: 0.86, blue: 0.57)

    private var recent: Bool {
        entry.verified && entry.checkedAt.map { abs(entry.date.timeIntervalSince($0)) < 5 * 60 } == true
    }
    private var hasData: Bool { entry.info != nil }
    private var connection: String {
        if !hasData { return "Not paired" }
        return recent ? "Reached at check" : "Not verified now"
    }
    private var connectionColor: Color { recent ? green : yellow }
    private var ram: String { entry.info?.heap.map { "\($0 / 1024) KB" } ?? "—" }
    private var block: String { entry.info?.heapBlock.map { "\($0 / 1024) KB" } ?? "—" }
    private var uptime: String {
        guard let n = entry.info?.uptime else { return "—" }
        if n >= 86400 { return "\(n / 86400)d \((n % 86400) / 3600)h" }
        if n >= 3600 { return "\(n / 3600)h \((n % 3600) / 60)m" }
        return "\(n / 60)m"
    }
    private var homeKit: String {
        guard let h = entry.info?.homekit else { return "—" }
        if h.connected == true { return "Connected" }
        return h.status ?? "Not connected"
    }
    private var relay: String {
        guard let r = entry.info?.remote else { return "—" }
        if r.on == false { return "Disabled" }
        return r.connected == true ? "Connected" : "Not connected"
    }
    private var sensor: String {
        guard let g = entry.info?.govee else { return "—" }
        switch g.source {
        case "equinox": return "Equinox"
        case "dewpoint": return "DewPoint"
        case "localBLE": return "Bridge BLE"
        case "stale": return "Stale"
        default: return g.feedActive == true ? "iPhone feed" : "No fresh data"
        }
    }
    private var warning: String? {
        guard let i = entry.info else { return nil }
        if i.boot?.safeMode == true { return "Safe mode" }
        if (i.boot?.crashes ?? 0) > 0 { return "\(i.boot?.crashes ?? 0) recent crashes" }
        if let heap = i.heap, heap < 40 * 1024 { return "Low free RAM" }
        if let blk = i.heapBlock, blk < 32 * 1024 { return "Small free RAM block" }
        return nil
    }
    private var observed: String {
        guard let seen = entry.checkedAt else { return "No reading yet" }
        return (recent ? "Checked " : "Last seen ") +
            seen.formatted(date: .omitted, time: .shortened)
    }
    private var subtitle: String {
        guard let i = entry.info else { return "Open Keystone to pair" }
        let ver = i.version ?? "?"
        return "FW \(ver)\(i.build.map { " · \($0)" } ?? "")"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label("Bridge \(recent ? "reached" : "unverified") · \(ram)", systemImage: "cpu")
            case .accessoryCircular:
                VStack(spacing: 1) {
                    Image(systemName: recent ? "checkmark.circle.fill" : "questionmark.circle")
                        .font(.system(size: 14))
                    Text(entry.info?.heap.map { "\($0 / 1024)K" } ?? "—")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("RAM").font(.system(size: 9))
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("Bridge · \(recent ? "Reached" : "Unverified")", systemImage: "cpu")
                        .font(.caption2.weight(.semibold))
                    Text("RAM \(ram) · up \(uptime)")
                        .font(.caption.weight(.semibold))
                    Text(observed).font(.caption2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .systemMedium:
                medium
            case .systemLarge:
                large
            default:
                small
            }
        }
        .widgetURL(URL(string: "keystone://health"))
    }

    private var heading: some View {
        HStack(spacing: 6) {
            Image(systemName: "cpu.fill").foregroundStyle(yellow)
            Text("BRIDGE HEALTH").font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.35)
                .foregroundStyle(.white.opacity(0.88))
            Spacer(minLength: 2)
            Circle().fill(connectionColor).frame(width: 8, height: 8)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
            Text(connection).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(connectionColor).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(ram).font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white).minimumScaleFactor(0.7)
            Text("Free RAM · block \(block)")
                .font(.system(size: 10)).foregroundStyle(cyan).lineLimit(1).minimumScaleFactor(0.8)
            Text(observed).font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading
            HStack(spacing: 7) {
                Text(connection).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(connectionColor).lineLimit(1)
                Spacer(minLength: 4)
                Text(observed).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                metric("Free RAM", ram, icon: "memorychip")
                metric("Largest block", block, icon: "square.stack.3d.up")
                metric("Uptime", uptime, icon: "clock")
            }
            Divider().overlay(.white.opacity(0.15))
            HStack(spacing: 12) {
                compact("HomeKit", homeKit)
                compact("Relay", relay)
                compact("Govee", sensor)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(connection).font(.headline).foregroundStyle(connectionColor)
                    Text(observed).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: recent ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .font(.title2).foregroundStyle(connectionColor)
            }
            HStack(spacing: 10) {
                metric("Free RAM", ram, icon: "memorychip")
                metric("Largest block", block, icon: "square.stack.3d.up")
            }
            Divider().overlay(.white.opacity(0.15))
            detail("Uptime", uptime, icon: "clock")
            detail("Apple Home", homeKit, icon: "house")
            detail("Remote relay", relay, icon: "antenna.radiowaves.left.and.right")
            detail("Govee source", sensor, icon: "thermometer")
            if let drops = entry.info?.homekit?.wifiDrops {
                detail("Wi-Fi drops / reconnects",
                       "\(drops) / \(entry.info?.homekit?.wifiReconnects ?? 0)",
                       icon: "wifi.exclamationmark")
            }
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(yellow)
            }
            Spacer(minLength: 0)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func metric(_ name: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(name, systemImage: icon)
                .font(.system(size: 10)).foregroundStyle(cyan).lineLimit(1)
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white).minimumScaleFactor(0.68).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compact(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ name: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(cyan)
            Text(name).font(.caption).foregroundStyle(.white.opacity(0.76))
            Spacer(minLength: 2)
            Text(value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

#if DEBUG
#Preview(as: .systemMedium) {
    BridgeHealthWidget()
} timeline: {
    BridgeHealthEntry.preview
}
#endif
