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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if store.paired { socketsCard; shortcutsCard } else { pairCard }
                    if let message = store.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Text("Installed version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))")
                        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(18)
            }
            .background(Color(red: 0.07, green: 0.09, blue: 0.13))
            .navigationTitle("Socket")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showingSettings) { settings }
            .refreshable { await store.refresh() }
            .task { if store.paired { await store.refresh() } }
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
                Label(store.reachable ? (store.strip?.ok == true ? "Online" : "Strip unavailable") : "Not connected",
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
            if store.sockets.isEmpty {
                Text("Set up the strip in Keystone → Bridge → Power strip first.")
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

    private var pairCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect Keystone").font(.headline)
            Text("Configure the power strip in the Keystone app first. Enter the ESP32 bridge's local IP (shown on Keystone's dashboard).")
                .font(.subheadline).foregroundStyle(.secondary)
            TextField("192.168.1.50", text: $store.host)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .padding(12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            Button { Task { await store.pair() } } label: {
                HStack {
                    if store.busy == "pair" { ProgressView().tint(.black) }
                    Text("Pair Socket")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.busy != nil || store.host.isEmpty)
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Siri & Shortcuts", systemImage: "bolt.fill").font(.headline)
            Text("Find Socket in Apple Shortcuts, then choose Control Socket → a named outlet → On, Off, or Toggle. Set All Sockets preserves a Keystone-labelled outlet when turning everything off.")
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
                        Button("Forget Socket pairing", role: .destructive) {
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
