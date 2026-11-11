import SwiftUI
import CoreImage.CIFilterBuiltins

/// Adds a Tuya / Smart Life power strip to the bridge without typing anything: sign in to Smart Life once,
/// tap the strip, and Keystone sends its ID, local key and outlets to the bridge, which finds the strip's
/// address on the Wi-Fi by itself. Setup only works on the home Wi-Fi (the key travels to the bridge).
struct StripSetupView: View {
    @EnvironmentObject var store: Store

    @AppStorage("tuyaUserCode") private var userCode = ""
    @State private var token = TuyaToken.stored
    @State private var devices: [TuyaDevice] = []
    @State private var loading = false
    @State private var qr: String?
    @State private var qrImage: UIImage?
    @State private var pollTask: Task<Void, Never>?
    @State private var message: String?
    @State private var working: String?
    @State private var restarting = false
    @State private var confirmRemove = false

    private var strip: BridgeInfo.Strip? { store.info?.strip?.configured == true ? store.info?.strip : nil }

    var body: some View {
        Form {
            if let s = strip { statusSections(s) }
            if restarting && strip == nil {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("The bridge is restarting so Apple Home gets the outlets, then it looks for the strip on your Wi-Fi. About a minute.")
                            .font(.footnote)
                    }
                }
            }
            if token == nil { loginSections } else if strip == nil && !restarting { pickSections }
            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(Theme.bad) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Power strip")
        .onDisappear { pollTask?.cancel() }
        .onChange(of: strip != nil) { _, has in if has { restarting = false } }
        .task { if token != nil, strip == nil, devices.isEmpty { await loadDevices() } }
        .confirmationDialog("Remove the power strip from the bridge and Apple Home?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await remove() } }
        }
    }

    // MARK: Already set up

    @ViewBuilder private func statusSections(_ s: BridgeInfo.Strip) -> some View {
        Section {
            LabeledContent("Strip", value: s.name ?? "Power strip")
            LabeledContent("Status", value: statusText(s))
            if let ip = s.ip, !ip.isEmpty { LabeledContent("Address", value: ip) }
            if s.scanning == true {
                ProgressView(value: Double(s.scanDone ?? 0), total: Double(max(1, s.scanTotal ?? 254)))
            }
            ForEach(Array((s.outlets ?? []).enumerated()), id: \.offset) { _, o in
                LabeledContent(o.name, value: "data point \(o.dp)")
            }
        } header: { Text("Power strip") }

        Section {
            Button("Look for it on Wi-Fi again") { Task { await findAgain() } }
                .disabled(s.scanning == true)
            if token != nil {
                Button { Task { await updateKey(s) } } label: {
                    HStack { Text("Update key from Smart Life"); Spacer(); if working == "key" { ProgressView() } }
                }
                .disabled(working != nil)
            }
            NavigationLink("Enter details by hand") { StripManualView().environmentObject(store) }
            Button("Remove the power strip", role: .destructive) { confirmRemove = true }
        } footer: {
            Text("Changed the strip's Wi-Fi or re-paired it? Its key changes too: update the key from Smart Life (sign in below if asked) and the bridge finds its new address on its own. The strip has to be on the same Wi-Fi as the bridge.")
        }
    }

    private func statusText(_ s: BridgeInfo.Strip) -> String {
        if s.scanning == true { return "Looking for it on Wi-Fi \(s.scanDone ?? 0)/\(s.scanTotal ?? 254)" }
        if (s.ip ?? "").isEmpty { return s.scan ?? "No address yet" }
        if s.ok == true { return "Connected" }
        return s.error ?? "Not answering"
    }

    // MARK: Sign in

    @ViewBuilder private var loginSections: some View {
        Section {
            if let qrImage, qr != nil {
                Text("Scan this in Smart Life").font(.headline)
                Image(uiImage: qrImage)
                    .interpolation(.none).resizable().scaledToFit()
                    .padding(12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
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
                    Button("Start over") { resetQR() }.font(.footnote)
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
        } header: {
            Text(strip == nil ? "Sign in to Smart Life" : "Sign in to Smart Life (to update the key)")
        } footer: {
            if qr == nil {
                Text("Once. In Smart Life: Me › ⚙︎ Settings › Account and Security › User Code. Paste it, get the QR, then in Smart Life tap + › Scan (pick the saved photo, or scan the screen from another device) and confirm. Keystone only reads the strip's ID, key and outlet names.")
            } else {
                Text("On this phone: share the QR and save it to Photos, open Smart Life, tap + › Scan, tap the photo icon and pick it. Confirm the login and come back here.")
            }
        }
        if strip == nil {
            Section { NavigationLink("Enter details by hand") { StripManualView().environmentObject(store) } }
        }
    }

    private func resetQR() {
        pollTask?.cancel()
        qr = nil
        qrImage = nil
    }

    private func getQR() async {
        let code = userCode.trimmingCharacters(in: .whitespacesAndNewlines)
        working = "qr"
        message = nil
        defer { working = nil }
        do {
            let t = try await TuyaLogin.requestQR(userCode: code)
            qr = t
            qrImage = Self.makeQR(TuyaConst.qrPrefix + t)
            startPolling(qr: t, userCode: code)
        } catch {
            message = error.localizedDescription
        }
    }

    private func startPolling(qr t: String, userCode code: String) {
        pollTask?.cancel()
        pollTask = Task {
            let started = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { return }
                if let got = try? await TuyaLogin.poll(qr: t, userCode: code) {
                    TuyaToken.stored = got
                    token = got
                    resetQR()
                    if strip == nil { await loadDevices() }
                    return
                }
                if Date().timeIntervalSince(started) > 280 {
                    message = "That QR expired. Get a new one."
                    resetQR()
                    return
                }
            }
        }
    }

    private static func makeQR(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "Q"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: Pick the strip

    @ViewBuilder private var pickSections: some View {
        Section {
            if loading {
                HStack { ProgressView(); Text("Loading your Smart Life devices…").foregroundStyle(.secondary) }
            } else if devices.isEmpty {
                Text("No devices found. The strip has to be in the Smart Life account you signed in with.").foregroundStyle(.secondary)
            }
            ForEach(devices.sorted { ($0.looksLikeStrip ? 0 : 1) < ($1.looksLikeStrip ? 0 : 1) }) { d in
                Button { Task { await add(d) } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: d.looksLikeStrip ? "poweroutlet.strip" : "square.grid.2x2")
                            .foregroundStyle(d.looksLikeStrip ? Theme.yellow : .secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).foregroundStyle(.white)
                            Text([d.productName, d.online ? nil : "Offline"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if working == d.id { ProgressView() } else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                    }
                }
                .disabled(working != nil)
            }
        } header: { Text("Pick your power strip") } footer: {
            Text("Tap it. Keystone reads its key and outlets from Smart Life and hands them to the bridge, which finds the strip on your Wi-Fi by itself and puts each outlet in Apple Home.")
        }
        Section {
            Button("Refresh the list") { Task { await loadDevices() } }
            Button("Sign out of Smart Life", role: .destructive) { signOut() }
            NavigationLink("Enter details by hand") { StripManualView().environmentObject(store) }
        }
    }

    private func client() -> TuyaClient? {
        guard let t = TuyaToken.stored ?? token else { return nil }
        return TuyaClient(token: t)
    }

    private func signOut() {
        TuyaToken.stored = nil
        token = nil
        devices = []
    }

    private func handle(_ error: Error) {
        if let t = error as? TuyaError, t.isAuth {
            signOut()
            message = t.message
        } else {
            message = error.localizedDescription
        }
    }

    private func loadDevices() async {
        guard let c = client() else { return }
        loading = true
        message = nil
        defer { loading = false }
        do { devices = try await c.allDevices() } catch { handle(error) }
    }

    private func add(_ d: TuyaDevice) async {
        guard let c = client() else { return }
        working = d.id
        message = nil
        defer { working = nil }
        do {
            let fresh = try await c.device(id: d.id) ?? d
            guard let key = fresh.localKey, key.count == 16 else {
                message = "Smart Life didn't give a local key for this device. Pick the strip itself, or enter the details by hand."
                return
            }
            let outlets = try await c.outlets(id: d.id)
            guard !outlets.isEmpty else {
                message = "Couldn't tell which of this device's data points are outlets. Use Enter details by hand."
                return
            }
            let body: [String: Any] = [
                "action": "config", "name": d.name, "id": d.id, "key": key, "ip": "", "ver": 3.3,
                "outlets": outlets.map { ["name": $0.name, "dp": $0.dp] },
            ]
            let r = try await BridgeAPI.post("/api/strip", body, store.link, timeout: 10)
            let restart = (r["restart"] as? Bool) == true
            restarting = restart
            store.show(restart ? "Added. The bridge is restarting so Home gets the outlets." : "Added.")
            if restart { store.reachable = false }
            await store.refresh()
        } catch {
            if error is TuyaError { handle(error) } else { message = "Setup needs your home Wi-Fi: \(error.localizedDescription)" }
        }
    }

    // MARK: Maintenance

    private func findAgain() async {
        do {
            try await BridgeAPI.post("/api/strip", ["action": "find"], store.link, timeout: 8)
            await store.refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    /// After re-pairing the strip: new local key from Smart Life, then look for it on the Wi-Fi again.
    private func updateKey(_ s: BridgeInfo.Strip) async {
        guard let c = client(), let id = s.id else { return }
        working = "key"
        message = nil
        defer { working = nil }
        do {
            guard let d = try await c.device(id: id), let key = d.localKey, key.count == 16 else {
                message = "Smart Life has no key for this strip. Is it still in the account you signed in with?"
                return
            }
            let body: [String: Any] = [
                "action": "config", "name": s.name ?? "Power Strip", "id": id, "key": key, "ip": "", "ver": s.ver ?? 3.3,
                "outlets": (s.outlets ?? []).map { ["name": $0.name, "dp": $0.dp] },
            ]
            try await BridgeAPI.post("/api/strip", body, store.link, timeout: 10)
            try await BridgeAPI.post("/api/strip", ["action": "find"], store.link, timeout: 8)
            store.show("Key updated. Looking for the strip on Wi-Fi.")
            await store.refresh()
        } catch {
            if error is TuyaError { handle(error) } else { message = "Needs your home Wi-Fi: \(error.localizedDescription)" }
        }
    }

    private func remove() async {
        do {
            try await BridgeAPI.post("/api/strip", ["action": "remove"], store.link, timeout: 10)
            store.show("Power strip removed. The bridge is restarting.")
            await store.refresh()
        } catch {
            message = error.localizedDescription
        }
    }
}
