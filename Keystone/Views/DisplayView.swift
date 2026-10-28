import SwiftUI

struct DisplayView: View {
    @EnvironmentObject var store: Store
    @State private var previewPage: DisplaySettings.Page = .clock

    private var d: DisplaySettings { store.display }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    OLEDPreview(page: previewPage, settings: d, info: store.info)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    Picker("Preview", selection: $previewPage) {
                        ForEach(DisplaySettings.Page.allCases) { p in Image(systemName: p.icon).tag(p) }
                    }
                    .pickerStyle(.segmented)
                    Button { Task { await store.identify() } } label: {
                        Label("Flash the bridge's screen", systemImage: "sparkles")
                    }
                } footer: {
                    if d.present == false {
                        Text("This bridge has no screen. These settings apply if you move to a board with one.")
                    }
                }

                Section {
                    Toggle("Screen on", isOn: bind(\.on))
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Brightness")
                            Spacer()
                            Text("\(Int(Double(d.bright) / 255 * 100))%").foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: Binding(get: { Double(d.bright) }, set: { v in store.setDisplay { $0.bright = Int(v) } }), in: 1...255)
                    }
                    Toggle("Upside down", isOn: bind(\.flip))
                } footer: {
                    Text("Upside down is for mounting it with the USB port on the left. OLEDs can burn in over months: a lower brightness and night mode help.")
                }

                Section {
                    ForEach(DisplaySettings.Page.allCases) { p in
                        Toggle(isOn: Binding(get: { d.has(p) }, set: { v in store.setDisplay { $0.set(p, v) } })) {
                            Label(p.title, systemImage: p.icon)
                        }
                    }
                    Picker("Each page for", selection: bind(\.cycle)) {
                        ForEach([3, 5, 6, 8, 10, 15, 30, 60], id: \.self) { Text("\($0) s").tag($0) }
                    }
                } header: {
                    Text("Pages")
                } footer: {
                    Text("It cycles through the pages that are on and have something to show. When the TV goes off, the lights-off countdown takes over the screen.")
                }

                Section("Units") {
                    Toggle("24-hour clock", isOn: bind(\.clock24))
                    Picker("Temperature", selection: bind(\.tempF)) {
                        Text("°C").tag(false)
                        Text("°F").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Night mode", isOn: bind(\.nightOn))
                    if d.nightOn {
                        DatePicker("From", selection: Binding(get: { d.nightFrom.asTime }, set: { v in store.setDisplay { $0.nightFrom = v.minutesOfDay } }),
                                   displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: Binding(get: { d.nightTo.asTime }, set: { v in store.setDisplay { $0.nightTo = v.minutesOfDay } }),
                                   displayedComponents: .hourAndMinute)
                        Picker("At night", selection: bind(\.nightMode)) {
                            Text("Dim clock").tag(1)
                            Text("Screen off").tag(0)
                        }
                        Toggle("Show the TV-off countdown anyway", isOn: bind(\.countdownWakes))
                    }
                } header: {
                    Text("Night")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Display")
        }
    }

    private func bind<T>(_ kp: WritableKeyPath<DisplaySettings, T>) -> Binding<T> {
        Binding(get: { store.display[keyPath: kp] }, set: { v in store.setDisplay { $0[keyPath: kp] = v } })
    }
}

/// A rough copy of what the bridge's 128x64 two-tone OLED shows.
struct OLEDPreview: View {
    let page: DisplaySettings.Page
    let settings: DisplaySettings
    let info: BridgeInfo?

    var body: some View {
        let dim = settings.bright < 40
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 11, weight: .bold))
                Spacer()
                if info?.tvIsOn == true { Image(systemName: "tv").font(.system(size: 10, weight: .bold)) }
                SignalBars(bars: Fmt.signal(info?.rssi).bars).foregroundStyle(Theme.yellow).scaleEffect(0.8)
            }
            .foregroundStyle(Theme.yellow)
            .padding(.horizontal, 6)
            .frame(height: 30)
            content(for: page)
                .foregroundStyle(Theme.blue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 6)
        }
        .frame(width: 256, height: 128)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15)))
        .rotationEffect(.degrees(settings.flip ? 180 : 0))
        .opacity(settings.on ? (dim ? 0.55 : 1) : 0.15)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.25), value: settings.flip)
    }

    private var now: String {
        let f = DateFormatter()
        f.dateFormat = settings.clock24 ? "HH:mm" : "h:mm"
        return f.string(from: .now)
    }

    private var title: String {
        switch page {
        case .clock:
            let f = DateFormatter()
            f.dateFormat = "EEE MMM d"
            return f.string(from: .now)
        case .room: return "Room  \(now)"
        case .air: return "Air  \(Fmt.aq(info?.purifier?.pm25))"
        case .lights: return "Lights  \(now)"
        case .tv: return "TV  \(now)"
        }
    }

    @ViewBuilder private func content(for p: DisplaySettings.Page) -> some View {
        let big = Font.system(size: 52, weight: .medium, design: .rounded)
        switch p {
        case .clock:
            Text(now).font(big).monospacedDigit()
        case .room:
            HStack(alignment: .lastTextBaseline) {
                Text(Fmt.temp(info?.govee?.temp ?? 21.5, f: settings.tempF)).font(big)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(Int((info?.govee?.humidity ?? 45).rounded()))%").font(.system(size: 22, weight: .bold))
                    Text("humidity").font(.system(size: 12))
                }
            }
        case .air:
            HStack(alignment: .lastTextBaseline) {
                Text("\(Int((info?.purifier?.pm25 ?? 4).rounded()))").font(big)
                Text("PM2.5").font(.system(size: 12))
                Spacer()
                Text(info?.purifier?.auto == true ? "auto" : "fan \(info?.purifier?.speed ?? 2)").font(.system(size: 18, weight: .bold))
            }
        case .lights:
            HStack(alignment: .lastTextBaseline) {
                Text("\(info?.lightsOn ?? 2)").font(big)
                Text("of \(info?.lights?.count ?? 4) on").font(.system(size: 18, weight: .bold))
                Spacer()
            }
        case .tv:
            VStack(alignment: .leading) {
                Text(info?.tvIsOn == true ? "On" : "Off").font(.system(size: 34, weight: .bold))
                Text("lights off after \(info?.learnedDelay ?? 60)s").font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
