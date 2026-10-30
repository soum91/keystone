import SwiftUI

/// Router calls through the bridge (LAN or the relay), so the router works from anywhere.
@MainActor
final class BridgeRouterLink: SwitchyardLink {
    var canSetUp: Bool { false }

    func call(_ method: String, _ args: [String: Any], timeout: Double) async throws -> [String: Any] {
        let r = try await BridgeAPI.post("/api/control", ["device": "router", "call": method, "args": args], timeout: timeout + 3)
        if let e = r["error"] as? String {
            if e.contains("plugin isn't on the router") { throw RouterError.notInstalled }
            throw RouterError.message(e)
        }
        return r
    }
}

struct RouterTab: View {
    @EnvironmentObject var store: Store
    @StateObject private var model = RouterModel(link: BridgeRouterLink())
    @State private var setup = false
    @State private var followBusy = false

    private var routerInfo: BridgeInfo.RouterLinkInfo? { store.info?.router }

    var body: some View {
        NavigationStack {
            Group {
                if routerInfo?.configured == true {
                    RouterDashboard(model: model, title: "Router", onForget: {
                        Task {
                            _ = try? await BridgeAPI.post("/api/control", ["device": "router", "forget": true])
                            await store.refresh()
                        }
                    }, extra: AnyView(followCard))
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { setup = true } label: { Image(systemName: "gearshape") }
                        }
                    }
                    .onAppear { model.start(every: store.viaRelay ? 6 : 3) }
                    .onDisappear { model.stop() }
                } else {
                    intro
                }
            }
            .sheet(isPresented: $setup) {
                RouterSetupSheet { await store.refresh() }
            }
        }
    }

    private var followCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            SwitchRow(icon: "lightbulb.2.fill", title: "Follow the room lights",
                      detail: "All bridge lights off turns the router lights off. Any light on brings them back.",
                      isOn: routerInfo?.follow == true, busy: followBusy) { on in
                Task {
                    followBusy = true
                    defer { followBusy = false }
                    do {
                        _ = try await BridgeAPI.post("/api/control", ["device": "router", "follow": on])
                        await store.refresh()
                    } catch {
                        model.say(error.localizedDescription)
                    }
                }
            }
        }
        .card()
    }

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    CardTitle(text: "Router", icon: "wifi.router")
                    if store.info == nil {
                        Text("Waiting for the bridge…").foregroundStyle(.secondary)
                    } else if routerInfo == nil {
                        Text("Update the bridge firmware first (Bridge › Update). Router control needs bridge build with router support.")
                            .font(.subheadline)
                    } else {
                        Text("Run the OpenWrt ASUS from here, at home or away. The bridge talks to the router, so it works over remote access too. Setup needs your home Wi-Fi once.")
                            .font(.subheadline)
                        Button("Set up the router") { setup = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.viaRelay)
                        if store.viaRelay {
                            Text("You're away from home right now. Setup works on your home Wi-Fi.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .card()
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Router")
    }
}

/// On the home network: root password -> router makes a Switchyard login -> the bridge keeps that login.
struct RouterSetupSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let done: () async -> Void
    @State private var host = "192.168.1.1"
    @State private var password = ""
    @State private var working: String?
    @State private var error: String?
    @State private var needsInstall = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Sign in with the router's root password once. The router creates a login that can only run Switchyard, and the bridge keeps that one. The root password isn't stored anywhere.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Router") {
                    TextField("Address", text: $host).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Root password", text: $password)
                }
                if needsInstall {
                    Section("One-time install") {
                        Text("The Switchyard plugin isn't on the router yet. SSH in (ssh root@\(host)) and run:").font(.footnote)
                        InstallCommand()
                    }
                }
                if let note { Section { Text(note).font(.footnote) } }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(Theme.bad) } }
                Section {
                    Button {
                        Task { await run() }
                    } label: {
                        HStack { Text(needsInstall ? "I ran it, try again" : "Connect"); if let w = working { Spacer(); Text(w).foregroundStyle(.secondary); ProgressView() } }
                    }
                    .disabled(working != nil || host.isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("Router setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func bridgeSetup(_ c: RouterSetup.Creds, host: String) async throws {
        _ = try await BridgeAPI.post("/api/control", ["device": "router", "setup": ["host": host, "user": c.user, "pass": c.pass]], timeout: 12)
    }

    private func run() async {
        error = nil
        note = nil
        defer { working = nil }
        do {
            working = "Router"
            let c = try await RouterSetup.provision(host: host, rootPassword: password)
            working = "Bridge"
            do {
                try await bridgeSetup(c, host: host)
            } catch {
                // The bridge is probably on the upstream network (Monty), outside the ASUS's LAN.
                // Let it in through the ASUS's firewall and point it at the ASUS's upstream address.
                guard let ip = store.info?.ip else { throw error }
                working = "Firewall"
                guard let upstream = try await RouterSetup.allow(host: host, rootPassword: password, ip: ip) else { throw error }
                working = "Bridge"
                try await bridgeSetup(c, host: upstream)
                note = "The bridge reaches the router at \(upstream) from the upstream network. If that network ever gives the router a new address, run setup again."
            }
            password = ""
            await done()
            if note == nil { dismiss() }
        } catch RouterError.notInstalled {
            needsInstall = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
