import SwiftUI
import UIKit

@main
struct SocketApp: App {
    @StateObject private var store = SocketStore.shared
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            SocketHome().environmentObject(store).tint(.mint).preferredColorScheme(.dark)
        }
        .onChange(of: phase, initial: true) { _, state in
            if state == .active && store.paired { Task { await store.refresh() } }
        }
    }
}

struct SocketHome: View {
    @EnvironmentObject var store: SocketStore
    @State private var showingSettings = false
    @State private var showManualAddress = false
    @StateObject private var finder = SurgeBridgeFinder()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if store.paired {
                        socketsCard
                        if store.strip?.configured == true { shortcutsCard }
                    } else { pairCard }
                    if let message = store.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Text("Installed version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))")
                        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(18)
            }
            .background(Color(red: 0.07, green: 0.09, blue: 0.13))
            .navigationTitle("Surge")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showingSettings) { settings }
            .refreshable { await store.refresh() }
            .task {
                if store.paired { await store.refresh() }
                else { finder.start() }
            }
            .onChange(of: finder.found) { _, hosts in
                if !store.paired && hosts.count == 1 {
                    store.host = hosts[0].host
                    store.port = hosts[0].port
                }
            }
            .onChange(of: store.paired) { _, paired in
                if paired { finder.stop() }
                else { finder.start() }
            }
            .onDisappear { finder.stop() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "poweroutlet.strip.fill")
                .font(.system(size: 26)).foregroundStyle(.mint)
                .frame(width: 54, height: 54)
                .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(store.strip?.name ?? "Power strip").font(.title2.bold())
                Label(store.reachable ? (store.strip?.configured != true ? "Bridge connected · outlets not set up" : store.strip?.ok == true ? "Online" : "Strip unavailable") : "Bridge offline",
                      systemImage: store.reachable ? "wifi" : "wifi.slash")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var socketsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Outlets").font(.headline)
                Spacer()
                Button("All on") { Task { await store.flipAll(to: true) } }
                Button("All off") { Task { await store.flipAll(to: false) } }
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .disabled(store.busy != nil || !store.reachable || store.strip?.ok != true)
            .padding(.bottom, 8)
            if store.strip?.configured != true {
                VStack(alignment: .leading, spacing: 12) {
                    Label("No outlet mappings on Keystone yet", systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.semibold))
                    Text("You connected the Surge app to the Keystone bridge, but the power strip was added in Apple Home as one generic plug. To get separate switches here, Keystone must register the strip's actual outlet data points.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        openKeystoneStripSetup()
                    } label: {
                        Label("Set up outlets in Keystone", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("In Keystone's Power strip screen, choose the same Joly Joy device from your existing Smart Life account. Or use Devices in Apple Home → the plug → Configure individual outlets for Surge.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
            } else if store.sockets.isEmpty {
                Text("The bridge has a strip configuration but reported no outlets. Open Keystone's Power strip setup and check its data point mapping.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 14)
            }
            ForEach(store.sockets) { socket in
                Divider().overlay(.white.opacity(0.1))
                HStack(spacing: 12) {
                    Image(systemName: socket.index >= 3 ? "cable.connector" : "poweroutlet.type.b")
                        .font(.title3).foregroundStyle(.mint).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(socket.name).font(.body.weight(.medium))
                        Text("Channel \(socket.index + 1) · DP \(socket.dp)")
                            .font(.caption2).foregroundStyle(.secondary)
                        if socket.powersBridge {
                            Text("May power Keystone — keep enabled")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if store.busy == socket.id { ProgressView() }
                    else {
                        Toggle(socket.name, isOn: Binding(
                            get: { socket.on == true },
                            set: { on in Task { await store.flip(socket, to: on) } }
                        ))
                        .labelsHidden()
                        .disabled(socket.on == nil || store.busy != nil ||
                                  !store.reachable || store.strip?.ok != true)
                    }
                }.padding(.vertical, 12)
            }
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private func openKeystoneStripSetup() {
        guard let url = URL(string: "keystone://power-strip") else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                Task { @MainActor in
                    store.message = "Open the Keystone app manually: Bridge → Power strip. Keystone's updated app supports opening that page directly."
                }
            }
        }
    }

    private var pairCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect Keystone").font(.headline)
            Text("Surge finds the existing Keystone ESP32 bridge automatically. Don't enter the power strip's own IP address.")
                .font(.subheadline).foregroundStyle(.secondary)
            if finder.searching && finder.found.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for Keystone on Wi-Fi…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !finder.found.isEmpty {
                ForEach(finder.found, id: \.host) { bridge in
                    Button {
                        store.host = bridge.host
                        store.port = bridge.port
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cpu.fill")
                                .foregroundStyle(.mint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(bridge.name).fontWeight(.semibold)
                                Text("\(bridge.host):\(bridge.port)")
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.host == bridge.host {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            if finder.found.isEmpty {
                Text(finder.searching ? "Make sure this iPhone and Keystone are on the same home Wi-Fi." :
                         "No Keystone bridge found. You can try another scan or enter its address manually.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("Scan again") { finder.start() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(showManualAddress ? "Hide manual IP" : "Enter IP manually") {
                    showManualAddress.toggle()
                }
                .font(.caption)
            }
            if showManualAddress || (finder.found.isEmpty && !finder.searching) {
                TextField("Bridge IP, not strip IP", text: $store.host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            } else if !store.host.isEmpty {
                Text("Selected bridge: \(store.host):\(store.port)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Button { Task { await store.pair() } } label: {
                HStack {
                    if store.busy == "pair" { ProgressView().tint(.black) }
                    Text("Pair with Keystone")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.busy != nil || store.host.isEmpty)
            Text("The bridge needs Keystone firmware build 175 or newer. Update from Keystone → Bridge → Firmware if prompted. Your Home pairing stays intact.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Siri & Shortcuts", systemImage: "bolt.fill").font(.headline)
            Text("Find Surge in Apple Shortcuts, then choose Control Socket → a named outlet → On, Off, or Toggle. Set All Sockets preserves a Keystone-labelled outlet when turning everything off.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Open Shortcuts") {
                if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Bridge") {
                    LabeledContent("Address", value: "\(store.host):\(store.port)")
                    LabeledContent("Status", value: store.paired ? "Paired" : "Not paired")
                    Button("Refresh") { Task { await store.refresh() } }
                    if store.paired {
                        Button("Forget Surge pairing", role: .destructive) {
                            Task { await store.forget() }
                        }
                    }
                }
                Section("Apple Home") {
                    Text("The existing Keystone ESP32 is the Apple Home bridge. No extra firmware or hardware. Your HomePod mini 2 handles automations.")
                }
                Section("Important") {
                    Text("Do not power off the socket supplying Keystone itself. All Off skips any outlet named Keystone, but individual toggles and Apple Home can still switch it off.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingSettings = false }
                }
            }
        }
    }
}
