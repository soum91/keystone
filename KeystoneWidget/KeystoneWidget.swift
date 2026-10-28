import WidgetKit
import SwiftUI

@main
struct KeystoneWidgets: WidgetBundle {
    var body: some Widget { RoomWidget() }
}

struct RoomEntry: TimelineEntry {
    let date: Date
    let info: BridgeInfo?
    let seen: Date?
    let live: Bool

    static let preview: RoomEntry = {
        let json = #"{"app":"afterglow-bridge","name":"Afterglow Bridge","govee":{"locked":true,"temp":21.6,"humidity":46,"battery":80},"tv":{"state":"standby"},"lights":[{"id":"a","name":"Desk","on":true},{"id":"b","name":"Strip","on":false}],"purifier":{"configured":true,"pm25":4,"on":true},"display":{"tempF":false}}"#
        let info = try? JSONDecoder().decode(BridgeInfo.self, from: Data(json.utf8))
        return RoomEntry(date: .now, info: info, seen: .now, live: true)
    }()
}

struct RoomProvider: TimelineProvider {
    func placeholder(in context: Context) -> RoomEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (RoomEntry) -> Void) {
        if context.isPreview, Snapshot.stored == nil { completion(.preview); return }
        let s = Snapshot.stored
        completion(RoomEntry(date: .now, info: s?.info, seen: s?.at, live: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoomEntry>) -> Void) {
        Task {
            var entry: RoomEntry
            let link = BridgeLink.stored
            if link.isSet, let i = try? await BridgeAPI.info(link, timeout: 3) {
                Snapshot.stored = Snapshot(info: i, at: .now)
                entry = RoomEntry(date: .now, info: i, seen: .now, live: true)
            } else {
                let s = Snapshot.stored
                entry = RoomEntry(date: .now, info: s?.info, seen: s?.at, live: false)
            }
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

struct RoomWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KeystoneRoom", provider: RoomProvider()) { e in
            RoomView(entry: e)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.1), Color(red: 0.02, green: 0.02, blue: 0.03)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Room")
        .description("Room temperature from the bridge's Govee sensor, plus the TV and lights.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct RoomView: View {
    let entry: RoomEntry
    @Environment(\.widgetFamily) private var family
    private let yellow = Color(red: 1.0, green: 0.84, blue: 0.04)
    private let blue = Color(red: 0.31, green: 0.76, blue: 0.97)

    private var f: Bool { entry.info?.display?.tempF ?? false }
    private var temp: String { Fmt.temp(entry.info?.govee?.temp, f: f) }
    private var hum: String { entry.info?.govee?.humidity.map { "\(Int($0.rounded()))%" } ?? "–" }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("\(temp) \(hum)", systemImage: "thermometer.medium")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "thermometer.medium").font(.system(size: 11))
                Text(temp).font(.system(size: 15, weight: .semibold))
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Room").font(.caption2.weight(.semibold))
                Text("\(temp)  \(hum)").font(.headline)
                Text(tvLine).font(.caption2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(spacing: 16) {
                tempBlock
                Divider().overlay(Color.white.opacity(0.15))
                VStack(alignment: .leading, spacing: 8) {
                    row("tv", tvLine)
                    row("lightbulb", "\(entry.info?.lightsOn ?? 0) of \(entry.info?.lights?.count ?? 0) lights on")
                    if let pm = entry.info?.purifier?.pm25 { row("aqi.medium", "PM2.5 \(Int(pm.rounded())) · \(Fmt.aq(pm))") }
                    Spacer(minLength: 0)
                    footer
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                tempBlock
                Spacer(minLength: 0)
                footer
            }
        }
    }

    private var tvLine: String {
        guard let s = entry.info?.tv?.state else { return "TV not set" }
        return "TV " + (s == "on" ? "on" : "off")
    }

    private var tempBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ROOM").font(.system(size: 11, weight: .bold)).foregroundStyle(yellow)
            Text(temp).font(.system(size: 36, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                .minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Image(systemName: "humidity")
                Text(hum)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(blue)
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(blue)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
    }

    private var footer: some View {
        Group {
            if entry.info == nil {
                Text("Open Keystone to pair")
            } else if entry.live {
                Text(entry.date, style: .time)
            } else if let s = entry.seen {
                Text("Away · \(s.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.white.opacity(0.4))
    }
}
