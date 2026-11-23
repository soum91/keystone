import SwiftUI
import UIKit

@main
struct SocketApp: App {
    @StateObject private var store = SocketStore.shared
    @StateObject private var cloud = SurgeCloudStore.shared
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            SocketHome().environmentObject(store).tint(.mint).preferredColorScheme(.dark)
        }
        .onChange(of: phase, initial: true) { _, state in
            if state == .active { Task {
                await store.refresh()
                await cloud.load()
            } }
        }
    }
}

struct SocketHome: View {
    @EnvironmentObject var store: SocketStore
    @StateObject private var cloud = SurgeCloudStore.shared
    @State private var showingSettings = false
    @State private var showManualAddress = false
    @StateObject private var finder = SurgeBridgeFinder()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if store.paired || (cloud.authorized && cloud.selected != nil) {
                        socketsCard
                        if !store.sockets.isEmpty { shortcutsCard }
                    } else { pairCard }
                    cloudCard
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
            .refreshable {
                await store.refresh()
                await cloud.load()
            }
            .task {
                finder.start() // Also rediscover after DHCP changed an existing pairing's IP.
                if store.paired { await store.refresh() }
                await cloud.load()
            }
            .onChange(of: finder.found) { _, hosts in
                guard hosts.count == 1 else { return }
                if store.paired {
                    if !store.reachable {
                        Task { await store.useDiscoveredBridge(host: hosts[0].host, port: hosts[0].port) }
                    }
                } else {
                    store.host = hosts[0].host
                    store.port = hosts[0].port
                }
            }
            .onChange(of: store.paired) { _, paired in
                if !paired { finder.start() }
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
                Text(store.usingCloud ? cloud.selected?.name ?? "Power strip" : store.strip?.name ?? "Power strip")
                    .font(.title2.bold())
                Label(store.usingCloud ? "Tuya Smart cloud fallback" :
                      store.reachable ? (store.strip?.configured != true ? "Bridge connected · outlets not set up" : store.strip?.ok == true ? "Keystone LAN connected" : "Strip unavailable") : "Keystone bridge offline",
                      systemImage: store.usingCloud ? "cloud" : store.reachable ? "wifi" : "wifi.slash")
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
            .disabled(store.busy != nil || store.sockets.isEmpty ||
                      (store.usingCloud ? !cloud.connected : !store.reachable || store.strip?.ok != true))
            .padding(.bottom, 8)
            if !store.usingCloud && store.strip?.configured != true {
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
                    Image(systemName: socket.name.hasPrefix("USB") ? "cable.connector" : "poweroutlet.type.b")
                        .font(.title3).foregroundStyle(.mint).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(socket.name).font(.body.weight(.medium))
                        Text(socket.code.map { "Tuya code \($0)" } ?? "Channel \(socket.index + 1) · DP \(socket.dp)")
                            .font(.caption2).foregroundStyle(.secondary)
                        if socket.powersBridge || cloud.protectedOutletIDs.contains(socket.id) {
                            Text("Protected from All Off")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if store.usingCloud {
                        Button {
                            cloud.setProtected(socket.id, !cloud.protectedOutletIDs.contains(socket.id))
                        } label: {
                            Image(systemName: cloud.protectedOutletIDs.contains(socket.id) ? "shield.fill" : "shield")
                                .foregroundStyle(cloud.protectedOutletIDs.contains(socket.id) ? .mint : .orange)
                        }
                        .accessibilityLabel("Protect \(socket.name) from All Off")
                    }
                    if store.busy == socket.id || cloud.busy == socket.id { ProgressView() }
                    else if store.usingCloud && socket.on == nil {
                        HStack {
                            Button("On") { Task { await store.flip(socket, to: true) } }
                            Button("Off") { Task { await store.flip(socket, to: false) } }
                        }
                        .buttonStyle(.bordered).font(.caption)
                    } else {
                        Toggle(socket.name, isOn: Binding(
                            get: { socket.on == true },
                            set: { on in Task { await store.flip(socket, to: on) } }
                        ))
                        .labelsHidden()
                        .disabled(socket.on == nil || store.busy != nil ||
                                  (store.usingCloud ? !cloud.connected : !store.reachable || store.strip?.ok != true))
                    }
                }.padding(.vertical, 12)
            }
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tuya Smart fallback", systemImage: "cloud.fill").font(.headline)
            Text("Control the actual reported Tuya outlet functions when Keystone's LAN connection is unavailable. This does not add cloud-only outlets to Apple Home.")
                .font(.subheadline).foregroundStyle(.secondary)
            if cloud.authorized {
                HStack {
                    Label(cloud.connected ? "Tuya connected" : "Tuya account saved", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { Task { await cloud.load() } }.font(.caption)
                }
                if !cloud.devices.isEmpty {
                    Picker("Power strip", selection: Binding(
                        get: { cloud.selectedID },
                        set: { cloud.select($0) }
                    )) {
                        Text("Choose strip").tag("")
                        ForEach(cloud.devices) { item in
                            Text(item.name + " (\(item.channels.count) controls)").tag(item.id)
                        }
                    }
                    Text("Switches shown: \(cloud.selected?.channels.count ?? 0), exactly as reported by Tuya Smart.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.usingCloud {
                    Text("For All Off, first tap the shield beside the outlet powering Keystone/HomePod. Other cloud outlets are individually controllable.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button("Sign out of Tuya Smart", role: .destructive) { cloud.signOut() }
                    .font(.caption)
            } else {
                Text("Sign in using Tuya Smart's User Code: Me → Settings → Account and Security → User Code.")
                    .font(.caption).foregroundStyle(.secondary)
                if let qr = cloud.qrImage {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                        .padding(10).background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .frame(maxWidth: 260).frame(maxWidth: .infinity)
                    ShareLink(item: Image(uiImage: qr), preview: SharePreview("Surge Tuya QR", image: Image(uiImage: qr))) {
                        Label("Share or save QR to Photos", systemImage: "square.and.arrow.up")
                    }
                    Button("Open Tuya Smart") { cloud.openTuyaApp() }
                    Button("Start over") { cloud.restartLogin() }.font(.caption)
                    Text("In Tuya Smart tap + → Scan → photo icon and select the saved QR. Return here after confirming.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("Tuya Smart user code", text: $cloud.userCode)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    Button("Get Tuya Smart login QR") { Task { await cloud.requestQR() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(cloud.busy != nil || cloud.userCode.isEmpty)
                }
            }
            if let note = cloud.message {
                Text(note).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
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
            Text("Surge finds Keystone automatically, even after its DHCP IP changes. Or sign in to Tuya Smart below for cloud fallback—no ESP32 pairing required.")
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
                Section("Tuya Smart fallback") {
                    Button("Refresh Tuya devices") { Task { await cloud.load() } }
                    Text("Cloud control is independent of Keystone. The Tuya public IP cannot be used as a LAN endpoint.")
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
