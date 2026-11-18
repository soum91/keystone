import SwiftUI

/// Every light, switch and plug on the Smart Life account, each with an Apple Home switch.
/// Keystone finds the device on the Wi-Fi and sends it straight to the bridge: no other app needed.
struct HomeDevicesView: View {
    @EnvironmentObject var store: Store
    @StateObject private var model = HomeDevices.shared
    @AppStorage("tuyaUserCode") private var userCode = ""
    @State private var token = TuyaToken.stored
    @State private var qr: String?
    @State private var qrImage: UIImage?
    @State private var pollTask: Task<Void, Never>?
    @State private var working: String?

    var body: some View {
        Form {
            if token == nil {
                loginSection
            } else {
                if let b = model.busy {
                    Section { HStack(spacing: 10) { ProgressView(); Text(b).font(.footnote) } }
                }
                deviceSections
                Section {
                    Button("Refresh from Smart Life") { Task { await reload() } }
                    Button("Look for them on Wi-Fi again") { Task { await model.find(); store.show(await model.push(store.link)) } }
                    Button("Sign out of Smart Life", role: .destructive) {
                        TuyaToken.stored = nil; token = nil
                    }
                } footer: {
                    Text("The bridge controls these over your Wi-Fi with each device's local key, so they keep working when the internet is down. Lights Afterglow already sent stay as they are; if you add the same one here, Keystone's copy is used.")
                }
            }
            if let m = model.message {
                Section { Text(m).font(.footnote).foregroundStyle(Theme.bad) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Devices in Apple Home")
        .onDisappear { pollTask?.cancel() }
        .task { if let t = token, model.devices.isEmpty { await model.refresh(t) } }
        .refreshable { await reload() }
    }

    private func reload() async {
        guard let t = token else { return }
        model.message = nil
        await model.refresh(t)
        if model.devices.contains(where: { $0.inHome && !$0.hasLocal }) { await model.find(model.devices.filter { $0.inHome && !$0.hasLocal }.map(\.id)) }
    }

    @ViewBuilder private var deviceSections: some View {
        let lights = model.devices.filter(\.isLight)
        let switches = model.devices.filter { !$0.isLight }
        if model.devices.isEmpty && model.busy == nil {
            Section { Text("No lights, switches or plugs on this Smart Life account.").foregroundStyle(.secondary) }
        }
        if !lights.isEmpty { Section("Lights") { ForEach(lights) { row($0) } } }
        if !switches.isEmpty { Section("Switches and plugs") { ForEach(switches) { row($0) } } }
    }

    private func row(_ d: HomeDevice) -> some View {
        let onBridge = store.info?.lights?.contains { $0.id == d.id } == true
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { d.inHome }, set: { v in
                Task { working = d.id; store.show(await model.setInHome(d.id, v, link: store.link)); working = nil; await store.refresh() }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name)
                    Text("\(d.kind)\(d.online ? "" : " · offline in Smart Life")").font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(working != nil || model.busy != nil)
            if working == d.id {
                Text("Working…").font(.caption).foregroundStyle(.secondary)
            } else if d.inHome, let why = d.problem {
                Text(why).font(.caption).foregroundStyle(Theme.bad)
            } else if d.inHome {
                Text(onBridge ? "In Apple Home · \(d.host ?? "")" : "Sent · \(d.host ?? "") (the bridge picks it up after restarting)")
                    .font(.caption).foregroundStyle(.secondary)
            } else if onBridge {
                Text("Already in Apple Home through Afterglow").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Sign in (same Smart Life login as the power strip)

    @ViewBuilder private var loginSection: some View {
        Section {
            if let qrImage, qr != nil {
                Text("Scan this in Smart Life").font(.headline)
                Image(uiImage: qrImage).interpolation(.none).resizable().scaledToFit()
                    .padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 260).frame(maxWidth: .infinity)
                ShareLink(item: Image(uiImage: qrImage), preview: SharePreview("Smart Life login", image: Image(uiImage: qrImage))) {
                    Label("Share or save the QR", systemImage: "square.and.arrow.up")
                }
                if let url = URL(string: "smartlife://") {
                    Link(destination: url) { Label("Open Smart Life", systemImage: "arrow.up.forward.app") }
                }
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to confirm in Smart Life…").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Start over") { pollTask?.cancel(); qr = nil; self.qrImage = nil }.font(.footnote)
                }
            } else {
                TextField("Smart Life user code", text: $userCode)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Button { Task { await getQR() } } label: {
                    HStack { Text("Get login QR"); Spacer(); if working == "qr" { ProgressView() } }
                }
                .disabled(working != nil || userCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: { Text("Sign in to Smart Life") } footer: {
            Text(qr == nil
                 ? "Once. In Smart Life: Me › ⚙︎ Settings › Account and Security › User Code. Paste it, get the QR, then in Smart Life tap + › Scan and confirm. Keystone reads your devices' names, IDs and local keys."
                 : "On this phone: share the QR and save it to Photos, open Smart Life, tap + › Scan, tap the photo icon and pick it. Confirm and come back.")
        }
    }

    private func getQR() async {
        let code = userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        working = "qr"; model.message = nil
        defer { working = nil }
        do {
            let t = try await TuyaLogin.requestQR(userCode: code)
            qr = t
            qrImage = StripSetupView.makeQR(TuyaConst.qrPrefix + t)
            pollTask?.cancel()
            pollTask = Task {
                let started = Date()
                while !Task.isCancelled && Date().timeIntervalSince(started) < 300 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if let got = try? await TuyaLogin.poll(qr: t, userCode: code) {
                        TuyaToken.stored = got
                        token = got; qr = nil; qrImage = nil
                        await model.refresh(got)
                        return
                    }
                }
            }
        } catch {
            model.message = error.localizedDescription
        }
    }
}
