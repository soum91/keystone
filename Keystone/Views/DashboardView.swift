import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 14) {
                        if let i = store.info {
                            header(i)
                            if let c = i.countdown { countdownCard(c) }
                            HStack(alignment: .top, spacing: 14) {
                                roomCard(i)
                                airCard(i)
                            }
                            if i.ac?.configured == true { acCard(i) }
                            tvCard(i)
                            lightsCard(i)
                            if i.bar?.configured == true { barCard(i) }
                            if let r = i.ir?.remotes, !r.isEmpty { irCard(r) }
                            eventsCard(i)
                        } else {
                            ProgressView().padding(.top, 80)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await store.refresh() }
            }
            .navigationTitle(store.info?.displayName ?? "Bridge")
        }
    }

    private var tempF: Bool { store.display.tempF }

    // MARK: Cards

    private func header(_ i: BridgeInfo) -> some View {
        HStack(spacing: 12) {
            Circle().fill(store.reachable ? Theme.good : Theme.bad).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.reachable ? "Online" : "Not reachable").fontWeight(.semibold)
                Text(store.reachable ? "\(i.ip ?? store.link.host) · up \(Fmt.uptime(i.uptime))"
                     : "Last seen \(store.lastSeen?.formatted(.relative(presentation: .named)) ?? "never")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    SignalBars(bars: Fmt.signal(i.rssi).bars)
                    Text(i.ssid ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text("v\(i.version ?? "?")\(i.build.map { " · build \($0)" } ?? "")").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func countdownCard(_ c: Int) -> some View {
        HStack {
            Image(systemName: "timer").font(.title2).foregroundStyle(Theme.yellow)
            VStack(alignment: .leading) {
                Text("TV went off").fontWeight(.semibold)
                Text("Lights off in \(c / 60):\(String(format: "%02d", c % 60))").font(.title3.monospacedDigit())
            }
            Spacer()
            Button("Pause rules") { Task { await store.setFollow(lights: false) } }
                .buttonStyle(.bordered)
        }
        .card()
    }

    private func roomCard(_ i: BridgeInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Room", icon: "thermometer.medium")
            if let g = i.govee, g.locked == true, let t = g.temp {
                Text(Fmt.temp(t, f: tempF)).font(.system(size: 34, weight: .semibold, design: .rounded))
                HStack(spacing: 10) {
                    Label("\(Int((g.humidity ?? 0).rounded()))%", systemImage: "humidity")
                    if let b = g.battery { Label("\(b)%", systemImage: b <= 15 ? "battery.25" : "battery.75") }
                }
                .font(.caption).foregroundStyle(.secondary)
            } else if i.govee?.locked == true {
                Text("Not heard lately").foregroundStyle(.secondary)
                Text("Is the Govee within a room of the bridge?").font(.caption).foregroundStyle(.secondary)
            } else if i.govee != nil {
                Text("Listening…").foregroundStyle(.secondary)
                Text("Picks the closest Govee sensor").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No Bluetooth on this board").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func airCard(_ i: BridgeInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Air", icon: "aqi.medium")
            if let p = i.purifier, p.configured == true {
                if let pm = p.pm25 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(pm.rounded()))").font(.system(size: 34, weight: .semibold, design: .rounded))
                        Text("PM2.5").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(Fmt.aq(pm)).font(.caption).foregroundStyle(.secondary)
                }
                Text(p.ok == false ? "Purifier not answering" : p.on == true ? (p.auto == true ? "Auto" : p.speed.map { "Fan \($0)" } ?? "On") : "Off")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No purifier").foregroundStyle(.secondary)
                Text("Send it from Exhale").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func acCard(_ i: BridgeInfo) -> some View {
        let a = i.ac!
        let modes = ["Fan", "Heat", "Cool", "Dry", "Auto"]
        let auto = a.auto?.enabled == true
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                CardTitle(text: a.name ?? "AC", icon: "air.conditioner.horizontal")
                Spacer()
                if a.ok == false { Text(a.error ?? "not answering").font(.caption).foregroundStyle(Theme.bad).lineLimit(1) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(a.on == true ? (auto ? "Smart Auto" : modes[min(4, max(0, a.mode ?? 2))]) : "Off")
                    .font(.title3.weight(.semibold))
                Spacer()
                if a.on == true, let t = a.target { Text("set \(t)°\(a.fahrenheit == true ? "F" : "C")").foregroundStyle(.secondary) }
            }
            if auto, let sp = a.auto?.setpoint, let b = a.auto?.band {
                Text(String(format: "Cools above %.1f°C, heats below %.1f°C", sp + b, sp - b) + (a.auto?.lastSwitchAgo.map { " · last switch \(Fmt.uptime($0)) ago" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let r = a.room { Text(String(format: "Room %.1f°C (what Smart Auto goes by)", r)).font(.caption).foregroundStyle(.secondary) }
        }
        .card()
    }

    private func tvCard(_ i: BridgeInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "TV", icon: "tv")
            HStack {
                Text(i.tv?.state.map { $0.capitalized } ?? "Not set").font(.title3.weight(.semibold))
                Spacer()
                if let d = i.learnedDelay {
                    Text("lights off after \(d) s\(i.samples.map { $0 >= 2 ? " (learned from \($0))" : "" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Toggle("Lights follow the TV", isOn: Binding(get: { i.followTV ?? true }, set: { v in Task { await store.setFollow(lights: v) } }))
            if i.bar?.configured == true {
                Toggle("Sound bar follows the TV", isOn: Binding(get: { i.barFollow ?? true }, set: { v in Task { await store.setFollow(bar: v) } }))
            }
            if let ins = i.tvTile?.inputs, !ins.isEmpty {
                Text("In Home with \(ins.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func lightsCard(_ i: BridgeInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle(text: "Lights", icon: "lightbulb")
                Spacer()
                Text("\(i.lightsOn) of \(i.lights?.count ?? 0) on").font(.caption).foregroundStyle(.secondary)
            }
            if (i.lights ?? []).isEmpty {
                Text("No lights yet. Send them from Afterglow.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(i.lights ?? []) { l in
                HStack {
                    Image(systemName: l.on == true ? "lightbulb.fill" : "lightbulb")
                        .foregroundStyle(l.ok == false ? Theme.bad : l.on == true ? Theme.yellow : .secondary)
                        .frame(width: 22)
                    Text(l.name)
                    Spacer()
                    Text(l.ok == false ? "not answering" : l.on == true ? "\(l.bri ?? 100)%" : "off")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func barCard(_ i: BridgeInfo) -> some View {
        HStack {
            CardTitle(text: "Sound bar", icon: "hifispeaker")
            Spacer()
            Text(i.bar?.state ?? "–").foregroundStyle(.secondary)
        }
        .card()
    }

    private func irCard(_ r: [BridgeInfo.IR.R]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "IR remotes", icon: "dot.radiowaves.right")
            ForEach(r, id: \.name) { x in
                HStack {
                    Text(x.name)
                    Spacer()
                    Text("power\((x.buttons ?? 0) > 0 ? " + \(x.buttons!) buttons" : "")").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private func eventsCard(_ i: BridgeInfo) -> some View {
        let all = (i.events ?? []).suffix(30)
        return VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: "Activity", icon: "list.bullet")
            if all.isEmpty { Text("Nothing yet.").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(all.reversed().enumerated()), id: \.offset) { _, e in
                Text(e).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}
