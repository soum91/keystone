import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: Store
    @State private var editing: KScene?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 14) {
                        problems
                        if let i = store.info {
                            header(i)
                            scenesCard(i)
                            if let c = i.countdown { countdownCard(c) }
                            HStack(alignment: .top, spacing: 14) {
                                roomCard(i)
                                airCard(i)
                            }
                            if i.ac?.configured == true { acCard(i) }
                            if let c = i.camera, c.configured == true { cameraCard(c, i) }
                            if let p = i.purifier, p.configured == true { purifierCard(p) }
                            tvCard(i)
                            lightsCard(i)
                            if i.bar?.configured == true { barCard(i) }
                            if let r = i.ir?.remotes, !r.isEmpty { irCard(r) }
                            eventsCard(i)
                        } else if store.lastError == nil {
                            ProgressView().padding(.top, 80)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await store.refresh() }
            }
            .navigationTitle(store.info?.displayName ?? "Bridge")
            .sheet(item: $editing) { sc in SceneEditor(scene: sc) }
        }
    }

    private var tempF: Bool { store.display.tempF }

    // MARK: Cards

    @ViewBuilder private var problems: some View {
        if store.forgotten {
            VStack(alignment: .leading, spacing: 8) {
                Label("The bridge doesn't know this phone anymore", systemImage: "exclamationmark.triangle.fill")
                    .fontWeight(.semibold).foregroundStyle(Theme.bad)
                Text("It was reset, so Keystone's old pairing and remote-access key are gone. Pair again at home: controls and remote access start working right away.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Pair again") { Task { await store.repair() } }.buttonStyle(.borderedProminent).tint(Theme.yellow).foregroundStyle(.black)
            }
            .card()
        } else if !store.reachable, let e = store.lastError {
            VStack(alignment: .leading, spacing: 6) {
                Label("Can't reach the bridge", systemImage: "wifi.exclamationmark").fontWeight(.semibold)
                Text(e).font(.caption).foregroundStyle(.secondary)
                Text(store.relay?.on == true ? "Keystone tried your Wi-Fi, then the remote relay." : "Remote access isn't set up on this phone yet: open Keystone once at home.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .card()
        }
    }


    private func header(_ i: BridgeInfo) -> some View {
        HStack(spacing: 12) {
            Circle().fill(store.reachable ? Theme.good : Theme.bad).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.reachable ? (store.viaRelay ? "Online · remote" : "Online") : "Not reachable").fontWeight(.semibold)
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

    private func scenesCard(_ i: BridgeInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle(text: "Scenes", icon: "sparkles")
                Spacer()
                Button {
                    editing = KScene(name: "", icon: "sparkles", actions: KScene.capture(i))
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                .accessibilityLabel("New scene from how things are now")
            }
            if store.scenes.isEmpty {
                Text("Set things the way you like, then tap + to save it as a scene.").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.scenes) { sc in
                        Button { Task { await store.runScene(sc) } } label: {
                            VStack(spacing: 6) {
                                if store.runningScene == sc.id { ProgressView().frame(height: 22) }
                                else { Image(systemName: sc.icon).font(.title3).frame(height: 22) }
                                Text(sc.name).font(.caption.weight(.medium)).lineLimit(1)
                            }
                            .frame(width: 84, height: 64)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(store.runningScene != nil)
                        .contextMenu {
                            Button { editing = sc } label: { Label("Edit", systemImage: "pencil") }
                            Button { var u = sc; u.actions = KScene.capture(i); editing = u } label: {
                                Label("Replace with how things are now", systemImage: "camera")
                            }
                            Button(role: .destructive) { store.deleteScene(sc) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
            }
            if !store.scenes.isEmpty {
                Text("Hold a scene to edit it. Siri: \"Run Movie in Keystone\".").font(.caption2).foregroundStyle(.secondary)
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
        let f = a.fahrenheit == true
        let targetC: Double? = auto ? a.auto?.setpoint : a.target.map { f ? (Double($0) - 32) * 5 / 9 : Double($0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle(text: a.name ?? "AC", icon: "air.conditioner.horizontal")
                Spacer()
                if a.ok == false { Text(a.error ?? "not answering").font(.caption).foregroundStyle(Theme.bad).lineLimit(2).multilineTextAlignment(.trailing) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(a.on == true ? (auto ? "Smart" : modes[min(4, max(0, a.mode ?? 2))]) : "Off")
                    .font(.title3.weight(.semibold))
                Spacer()
                Toggle("", isOn: Binding(get: { a.on == true }, set: { v in Task { await store.control(["device": "ac", "on": v]) } }))
                    .labelsHidden()
            }
            Picker("Mode", selection: Binding(
                get: { auto ? "smart" : ["fan", "heat", "cool", "dry", "auto"][min(4, max(0, a.mode ?? 2))] },
                set: { m in Task { await store.control(["device": "ac", "mode": m]) } })) {
                Text("Cool").tag("cool")
                Text("Heat").tag("heat")
                Text("Fan").tag("fan")
                Text("Dry").tag("dry")
                Text("Smart").tag("smart")
                Text("Auto").tag("auto")
            }
            .pickerStyle(.segmented)
            if let t = targetC {
                HStack {
                    Text(auto ? "Aim for" : "Set to").foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await store.control(["device": "ac", "target": t - (f ? 5.0 / 9 : (auto ? 1 : 0.5))]) } } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                    Text(Fmt.temp(t, f: tempF)).font(.title3.monospacedDigit().weight(.semibold)).frame(minWidth: 70)
                    Button { Task { await store.control(["device": "ac", "target": t + (f ? 5.0 / 9 : (auto ? 1 : 0.5))]) } } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
                .buttonStyle(.plain).foregroundStyle(Theme.yellow)
            }
            if auto, let b = a.auto?.band {
                HStack {
                    Text(String(format: "Switch at ±%.0f°C", b)).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await store.control(["device": "ac", "band": max(1, b - 1)]) } } label: { Image(systemName: "minus.circle") .font(.title3) }
                    Button { Task { await store.control(["device": "ac", "band": min(6, b + 1)]) } } label: { Image(systemName: "plus.circle").font(.title3) }
                }
                .buttonStyle(.plain).foregroundStyle(Theme.yellow)
            }
            if auto, let sp = a.auto?.setpoint, let b = a.auto?.band {
                Text(String(format: "Cools above %.1f°C, heats below %.1f°C", sp + b, sp - b) + (a.auto?.lastSwitchAgo.map { " · last switch \(Fmt.uptime($0)) ago" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let r = a.room { Text(String(format: "Room %.1f°C (what Smart Auto goes by)", r)).font(.caption).foregroundStyle(.secondary) }
        }
        .card()
    }

    private func purifierCard(_ p: BridgeInfo.Purifier) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle(text: p.name ?? "Purifier", icon: "wind")
                Spacer()
                Toggle("", isOn: Binding(get: { p.on == true }, set: { v in Task { await store.control(["device": "purifier", "on": v]) } }))
                    .labelsHidden()
            }
            HStack {
                Toggle("Auto", isOn: Binding(get: { p.auto == true }, set: { v in Task { await store.control(["device": "purifier", "auto": v]) } }))
                    .fixedSize()
                Spacer()
                if let sp = p.speed, p.auto != true {
                    Button { Task { await store.control(["device": "purifier", "speed": max(1, sp - 1)]) } } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                    Text("Fan \(sp)").monospacedDigit().frame(minWidth: 50)
                    Button { Task { await store.control(["device": "purifier", "speed": sp + 1]) } } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                } else if p.auto != true {
                    Button("Fan 1") { Task { await store.control(["device": "purifier", "speed": 1]) } }
                }
            }
            .buttonStyle(.plain).foregroundStyle(Theme.yellow)
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
            if i.tv?.host?.isEmpty == false {
                HStack(spacing: 10) {
                    Button { Task { await store.control(["device": "tv", "on": !i.tvIsOn]) } } label: {
                        Label(i.tvIsOn ? "Turn off" : "Turn on", systemImage: "power")
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.yellow).foregroundStyle(.black)
                    Spacer()
                    Button { Task { await store.control(["device": "tv", "vol": "down"]) } } label: { Image(systemName: "speaker.minus.fill") }
                        .buttonStyle(.bordered)
                    Button { Task { await store.control(["device": "tv", "vol": "up"]) } } label: { Image(systemName: "speaker.plus.fill") }
                        .buttonStyle(.bordered)
                    if let ins = i.tvTile?.inputs, !ins.isEmpty {
                        Menu {
                            ForEach(Array(ins.enumerated()), id: \.offset) { n, name in
                                Button(name) { Task { await store.control(["device": "tv", "input": n]) } }
                            }
                        } label: { Image(systemName: "rectangle.on.rectangle") }
                        .buttonStyle(.bordered)
                    }
                }
            }
            Toggle("Lights follow the TV", isOn: Binding(get: { i.followTV ?? true }, set: { v in Task { await store.setFollow(lights: v) } }))
            if i.bar?.configured == true {
                Toggle("Sound bar follows the TV", isOn: Binding(get: { i.barFollow ?? true }, set: { v in Task { await store.setFollow(bar: v) } }))
            }
        }
        .card()
    }

    private func lightsCard(_ i: BridgeInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardTitle(text: "Lights", icon: "lightbulb")
                Spacer()
                Text("\(i.lightsOn) of \(i.lights?.count ?? 0) on").font(.caption).foregroundStyle(.secondary)
            }
            if (i.lights ?? []).isEmpty {
                Text("No lights yet. Send them from Afterglow.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array((i.lights ?? []).enumerated()), id: \.element.id) { n, l in
                LightRow(light: l) { body in
                    var b = body
                    b["device"] = "light"
                    b["idx"] = n
                    Task { await store.control(b) }
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
            Button("On") { Task { await store.control(["device": "bar", "on": true]) } }.buttonStyle(.bordered)
            Button("Off") { Task { await store.control(["device": "bar", "on": false]) } }.buttonStyle(.bordered)
        }
        .card()
    }

    private func irCard(_ r: [BridgeInfo.IR.R]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "IR remotes", icon: "dot.radiowaves.right")
            ForEach(Array(r.enumerated()), id: \.offset) { n, x in
                VStack(alignment: .leading, spacing: 6) {
                    Text(x.name).fontWeight(.medium)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if x.power != false {
                                Button { Task { await store.control(["device": "ir", "remote": n, "button": -1]) } } label: { Label("Power", systemImage: "power") }
                                    .buttonStyle(.borderedProminent).tint(Theme.yellow).foregroundStyle(.black)
                            }
                            ForEach(Array((x.names ?? []).enumerated()), id: \.offset) { b, name in
                                Button(name) { Task { await store.control(["device": "ir", "remote": n, "button": b]) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .card()
    }

    private func cameraCard(_ c: BridgeInfo.Camera, _ i: BridgeInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardTitle(text: c.name ?? "Camera", icon: "video")
                Spacer()
                if let b = c.battery {
                    Label("\(b)%", systemImage: c.charging == true ? "battery.100percent.bolt" : b <= 15 ? "battery.25" : "battery.75")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                Label(c.person == true ? "Person" : c.motion == true ? "Motion" : "Quiet",
                      systemImage: c.person == true ? "figure.walk" : c.motion == true ? "waveform.path.ecg" : "moon.zzz")
                    .font(.headline)
                    .foregroundStyle(c.person == true || c.motion == true ? Color.orange : .primary)
                Spacer()
                if let ago = c.lastEventAgo {
                    Text("\(c.lastType == "person" ? "Person" : "Motion") \(Self.ago(ago))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let err = c.error, c.ok != true {
                Label(err, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            } else if c.online == false {
                Label("Camera offline", systemImage: "wifi.slash").font(.caption).foregroundStyle(.orange)
            }
            if let r = c.rule, r.enabled == true {
                Text(Self.ruleText(r, i)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private static func ruleText(_ r: BridgeInfo.Camera.Rule, _ i: BridgeInfo) -> String {
        let names: [String] = (r.lights ?? []).compactMap { id in i.lights?.first(where: { $0.id == id })?.name }
        var t = "Person turns on " + (names.isEmpty ? "lights" : names.joined(separator: ", "))
        if r.window == true { t += " between " + clock(r.from ?? 0) + " and " + clock(r.to ?? 0) }
        if let off = r.offIn, off > 0 { t += " · off in " + (off < 60 ? "\(off)s" : "\(off / 60)m") }
        return t
    }

    private static func ago(_ s: Int) -> String {
        s < 60 ? "\(s)s ago" : s < 3600 ? "\(s / 60)m ago" : "\(s / 3600)h ago"
    }

    private static func clock(_ m: Int) -> String {
        var c = DateComponents(); c.hour = m / 60; c.minute = m % 60
        return Calendar.current.date(from: c).map { $0.formatted(date: .omitted, time: .shortened) } ?? "\(m / 60):\(m % 60)"
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

/// One light: tap to switch, slide to dim (sent when you let go).
struct LightRow: View {
    let light: BridgeInfo.Light
    let send: ([String: Any]) -> Void
    @State private var bri: Double = 100
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: light.on == true ? "lightbulb.fill" : "lightbulb")
                    .foregroundStyle(light.ok == false ? Theme.bad : light.on == true ? Theme.yellow : .secondary)
                    .frame(width: 22)
                Text(light.name)
                Spacer()
                if light.ok == false { Text("not answering").font(.caption).foregroundStyle(.secondary) }
                Toggle("", isOn: Binding(get: { light.on == true }, set: { v in send(["on": v]) })).labelsHidden()
            }
            if light.on == true {
                HStack {
                    Image(systemName: "sun.min").foregroundStyle(.secondary)
                    Slider(value: $bri, in: 1...100) { editing in
                        dragging = editing
                        if !editing { send(["bri": Int(bri)]) }
                    }
                    .tint(Theme.yellow)
                    Text("\(Int(bri))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40)
                }
            }
        }
        .onAppear { bri = Double(light.bri ?? 100) }
        .onChange(of: light.bri) { _, v in if !dragging, let v { bri = Double(v) } }
    }
}

/// Name a scene and choose which of the captured device states it sets.
struct SceneEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var scene: KScene
    @State private var off: Set<UUID> = []

    private let icons = ["sparkles", "power", "film", "moon.stars", "sun.max", "sofa", "bed.double", "gamecontroller", "book", "figure.walk", "house", "snowflake"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Movie night", text: $scene.name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(icons, id: \.self) { ic in
                                Image(systemName: ic)
                                    .frame(width: 36, height: 36)
                                    .background(scene.icon == ic ? Theme.yellow.opacity(0.3) : .clear, in: Circle())
                                    .onTapGesture { scene.icon = ic }
                            }
                        }
                    }
                }
                Section {
                    ForEach(scene.actions) { a in
                        Toggle(a.label, isOn: Binding(get: { !off.contains(a.id) },
                                                     set: { v in if v { off.remove(a.id) } else { off.insert(a.id) } }))
                    }
                } header: { Text("What it sets") } footer: {
                    Text("Taken from how things are right now. Untick anything the scene should leave alone. To change a value, set the device on the dashboard, then hold the scene › Replace with how things are now.")
                }
            }
            .navigationTitle(scene.name.isEmpty ? "New scene" : scene.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var s = scene
                        s.name = s.name.trimmingCharacters(in: .whitespaces)
                        s.actions.removeAll { off.contains($0.id) }
                        store.saveScene(s)
                        dismiss()
                    }
                    .disabled(scene.name.trimmingCharacters(in: .whitespaces).isEmpty || scene.actions.count == off.count)
                }
            }
        }
    }
}
