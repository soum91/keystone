import SwiftUI

struct BridgeView: View {
    @EnvironmentObject var store: Store
    @State private var name = ""
    @State private var confirm: Confirm?

    enum Confirm: String, Identifiable {
        case restart, wifi, govee, forget
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let i = store.info {
                    Section {
                        TextField("Name", text: $name)
                            .onAppear { if name.isEmpty { name = i.displayName } }
                        if name.trimmingCharacters(in: .whitespaces) != i.displayName && !name.isEmpty {
                            Button("Rename") {
                                Task { await store.admin("rename", ["name": name.trimmingCharacters(in: .whitespaces)], done: "Renamed.") }
                            }
                        }
                    } header: {
                        Text("Name in Apple Home")
                    } footer: {
                        Text("Renaming restarts the bridge. Your Home setup, rooms and automations stay.")
                    }

                    Section {
                        LabeledContent("Firmware", value: "\(i.version ?? "?")\(i.build.map { " · build \($0)" } ?? "")")
                        if store.updateAvailable, let l = store.latest {
                            Button { Task { await store.installUpdate() } } label: {
                                Label("Update to build \(l.build)", systemImage: "arrow.down.circle.fill")
                            }
                            .disabled(store.updateRunning)
                        } else if store.latest != nil {
                            LabeledContent("Updates", value: "Up to date")
                        }
                        if let u = store.updating { Text(u).font(.footnote).foregroundStyle(.secondary) }
                        Button("Check for updates") { Task { await store.checkFirmware() } }
                    } header: {
                        Text("Firmware")
                    } footer: {
                        Text("Downloads from GitHub and goes to the bridge over Wi-Fi. Wi-Fi, pairings and the Home setup are kept.")
                    }

                    Section {
                        if let r = i.remote {
                            Toggle("Reach the bridge from anywhere", isOn: Binding(
                                get: { r.on ?? false },
                                set: { v in Task { await store.setRemote(on: v) } }))
                                .disabled(store.viaRelay)
                            LabeledContent("Relay", value: r.on == true ? (r.connected == true ? "Connected" : (r.error ?? "Connecting…")) : "Off")
                            LabeledContent("This phone", value: store.relay?.on == true ? (store.viaRelay ? "Using it now" : "Ready for when you're away") : "Not set up")
                            if !store.viaRelay {
                                Button("New key (logs out other phones)") { Task { await store.setRemote(rotate: true) } }
                            }
                        } else {
                            Text("Update the firmware to 1.6 or newer for remote access.").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Remote access")
                    } footer: {
                        Text("Away from home, Keystone talks to the bridge through a public MQTT relay. Everything is encrypted end to end with a key that never leaves your home Wi-Fi, so the relay only sees noise. Firmware updates still need home Wi-Fi.")
                    }

                    if let b = i.boot {
                        Section {
                            LabeledContent("Last start", value: (b.reason ?? "?").capitalized)
                            if let c = b.crashes, c > 0 { LabeledContent("Crashes in a row", value: "\(c)") }
                            if let h = i.heap { LabeledContent("Free memory", value: "\(h / 1024) KB") }
                            if let m = b.minHeap { LabeledContent("Lowest since start", value: "\(m / 1024) KB") }
                            if let blk = i.heapBlock { LabeledContent("Largest free block", value: "\(blk / 1024) KB") }
                            if b.safeMode == true {
                                Button("Restart in normal mode") { Task { await store.admin("normal", done: "Restarting normally.") } }
                            }
                        } header: {
                            Text("Health")
                        } footer: {
                            Text(b.safeMode == true
                                 ? "Safe mode: the bridge crashed twice in a row, so the AC and remote access are paused. Lights and Home still work. If it lands back here after restarting, send these numbers."
                                 : "Free memory under about 40 KB, or a crash as the last start, points to a problem.")
                        }
                    }

                    Section("Network") {
                        LabeledContent("Wi-Fi", value: i.ssid ?? "–")
                        LabeledContent("Signal", value: Fmt.signal(i.rssi).text)
                        LabeledContent("Address", value: i.ip ?? store.link.host)
                        LabeledContent("Up", value: Fmt.uptime(i.uptime))
                        LabeledContent("Chip", value: (i.chip ?? "?").uppercased())
                    }

                    Section {
                        pairingRow("Afterglow", "lights, TV", i.paired?.afterglow, app: "afterglow")
                        pairingRow("Subwave", "sound bar", i.paired?.subwave, app: "subwave")
                        pairingRow("Exhale", "air purifier", i.paired?.exhale, app: "exhale")
                        pairingRow("Redshift", "IR remotes", i.paired?.redshift, app: "redshift")
                        pairingRow("Equinox", "air conditioner", i.paired?.equinox, app: "equinox")
                        if let n = i.paired?.nightjar { pairingRow("Nightjar", "camera", n, app: "nightjar") }
                    } header: {
                        Text("Apps paired with the bridge")
                    } footer: {
                        Text("Reset one if you reinstalled that app and it can't pair again. What it already put in Home stays.")
                    }

                    if i.govee != nil {
                        Section {
                            LabeledContent("Thermometer", value: i.govee?.name ?? "not picked yet")
                            Button("Pick a different Govee sensor") { confirm = .govee }
                        } footer: {
                            Text("The bridge restarts and locks onto the strongest Govee sensor it hears in 30 s, so hold the right one close.")
                        }
                    }

                    Section {
                        Button("Restart the bridge") { confirm = .restart }
                        Button("Change Wi-Fi network", role: .destructive) { confirm = .wifi }
                    } footer: {
                        Text("Changing Wi-Fi puts the bridge back into setup: join HomeSpan-Setup from your phone and pick the new network.")
                    }
                } else {
                    Section {
                        Text("Waiting for the bridge…").foregroundStyle(.secondary)
                        if let e = store.lastError { Text(e).font(.caption).foregroundStyle(.secondary) }
                        LabeledContent("Remote access on this phone", value: store.relay?.on == true ? "Set up" : "Not set up")
                    }
                }

                Section {
                    LabeledContent("Keystone talks to", value: "\(store.link.host):\(store.link.port)")
                    Button("Forget this bridge in Keystone", role: .destructive) { confirm = .forget }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Bridge")
            .confirmationDialog(title, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
                switch confirm {
                case .restart: Button("Restart") { Task { await store.admin("restart", done: "Restarting.") } }
                case .wifi: Button("Forget Wi-Fi", role: .destructive) { Task { await store.admin("forgetWifi", done: "Wi-Fi forgotten.") } }
                case .govee: Button("Pick again") { Task { await store.admin("forgetGovee", done: "Picking again.") } }
                case .forget: Button("Forget", role: .destructive) { store.forget() }
                case nil: EmptyView()
                }
            }
        }
    }

    private var title: String {
        switch confirm {
        case .restart: return "Restart the bridge? Home shows it as not responding for about 20 s."
        case .wifi: return "Forget its Wi-Fi? It goes back to setup mode until you pick a network again."
        case .govee: return "Forget the Govee sensor and pick again?"
        case .forget: return "Forget the bridge in Keystone? The bridge itself keeps working."
        case nil: return ""
        }
    }

    private func pairingRow(_ name: String, _ what: String, _ paired: Bool?, app: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                Text(what).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if paired == true {
                Button("Reset") { Task { await store.admin("resetPairing", ["app": app], done: "\(name) can pair again.") } }
                    .buttonStyle(.bordered)
                    .font(.caption)
            } else {
                Text("not paired").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
