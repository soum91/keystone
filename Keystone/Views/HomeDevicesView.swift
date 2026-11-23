import SwiftUI

/// Every light, switch and plug on the Smart Life account, each with an Apple Home switch.
/// Keystone finds the device on the Wi-Fi and sends it straight to the bridge: no other app needed.
struct HomeDevicesView: View {
    @EnvironmentObject var store: Store
    @StateObject private var model = HomeDevices.shared
    @AppStorage("tuyaUserCode") private var userCode = ""
    @State private var token = TuyaToken.stored
    @State private var reconnecting = false
    @State private var qr: String?
    @State private var qrImage: UIImage?
    @State private var pollTask: Task<Void, Never>?
    @State private var working: String?
    @State private var surgeCandidate: HomeDevice?
    @State private var surgeMessage: String?
    @State private var surgeDeviceID: String?

    var body: some View {
        Form {
            if token == nil || reconnecting {
                loginSection
                if reconnecting {
                    Button("Cancel reconnect") { reconnecting = false }
                }
            } else {
                if let b = model.busy {
                    Section { HStack(spacing: 10) { ProgressView(); Text(b).font(.footnote) } }
                }
                if !model.devices.isEmpty {
                    Section {
                        Button {
                            Task { working = "all"; store.show(await model.addAll(link: store.link)); working = nil; await store.refresh() }
                        } label: {
                            HStack { Label("Put everything in Apple Home", systemImage: "house.fill"); Spacer(); if working == "all" { ProgressView() } }
                        }
                        .disabled(working != nil || model.busy != nil)
                    } footer: {
                        Text("Every light, switch and plug on your Smart Life account, plus your air purifier, in one go. The bridge restarts once (about 20 s).")
                    }
                }
                deviceSections
                Section {
                    Button("Refresh from Smart Life") { Task { await reload() } }
                    Button("Look for them on Wi-Fi again") {
                        Task {
                            working = "find"
                            defer { working = nil }
                            await model.find(link: store.link)
                            store.show(await model.push(store.link))
                            if model.syncFailure == nil, model.devices.contains(where: { $0.isPurifier && $0.inHome }) {
                                store.show(await model.pushPurifier(store.link))
                            }
                            await store.refresh()
                        }
                    }
                    .disabled(working != nil || model.busy != nil)
                    Button("Reconnect Tuya Smart") { reconnecting = true }
                    Button("Sign out of Tuya Smart", role: .destructive) {
                        TuyaToken.stored = nil; token = nil
                    }
                } footer: {
                    Text("Apple Home requires a verified local Tuya connection. Cloud-only devices can now be switched in Keystone directly through your QR-authorized Tuya Smart account while this app is open. Cloud controls require internet and are separate from Apple Home; the bridge's existing local devices remain unchanged.")
                }
            }
            if let m = model.message {
                Section { Text(m).font(.footnote).foregroundStyle(Theme.bad) }
            }
            if let failure = model.syncFailure {
                Section {
                    Text(failure).font(.footnote).foregroundStyle(Theme.bad)
                    Text("No bridge changes are confirmed. Your selections are kept on this phone for retry.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Apple Home sync failed") }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Devices in Apple Home")
        .onDisappear { pollTask?.cancel() }
        .task { if let t = token, model.devices.isEmpty { await model.refresh(t) } }
        .refreshable { await reload() }
        .confirmationDialog("Expose this strip's individual outlets?", isPresented: Binding(
            get: { surgeCandidate != nil },
            set: { if !$0 { surgeCandidate = nil } }),
            titleVisibility: .visible) {
            if let device = surgeCandidate {
                Button("Configure for Surge") {
                    let selected = device
                    surgeCandidate = nil
                    Task { await configureForSurge(selected) }
                }
            }
            Button("Cancel", role: .cancel) { surgeCandidate = nil }
        } message: {
            Text("Keystone will check the device's actual Tuya data-point IDs and authenticate to it over local Wi-Fi before registering individual switches. If verification fails, the reason and raw DP options will be shown under this plug. Nothing will be deleted from Apple Home.")
        }
    }

    /// Configure the separate strip only when Tuya's actual DP IDs and an authenticated
    /// LAN response agree. A generic "plug" with an unresponsive local endpoint is not
    /// proof its individual relays can be controlled.
    private func configureForSurge(_ device: HomeDevice) async {
        surgeDeviceID = device.id
        surgeMessage = "Checking Tuya data points and the local strip connection…"
        guard let session = TuyaToken.stored ?? token else {
            surgeMessage = "Tuya Smart login is missing. Sign in under Devices in Apple Home first."
            return
        }
        guard store.info?.features?.strip != false else {
            surgeMessage = "The bridge's Power strip feature is off. Enable it under Keystone → Bridge → Devices on the bridge, then try again."
            return
        }
        if store.info?.strip?.configured == true, store.info?.strip?.id != device.id {
            surgeMessage = "Keystone already has a different strip configured. Open Bridge → Power strip to review it first."
            return
        }
        working = device.id
        defer { working = nil }
        let client = TuyaClient(token: session)
        // The cloud details endpoint can omit a device that the already-saved
        // Smart Life home list knows. Preserve the known key as a fallback.
        let latest = try? await client.device(id: device.id)
        guard let key = latest?.localKey ?? device.localKey, key.count == 16 else {
            surgeMessage = "Tuya Smart did not provide a usable local key. This plug cannot be controlled reliably over LAN. Open the DP detector below; do not guess a key."
            return
        }
        var dpMap = device.dpMap
        if let freshCodes = try? await client.dpCodes(id: device.id) {
            dpMap.merge(freshCodes) { _, new in new }
        }
        let channels = TuyaClient.stripOutlets(from: dpMap)
        // Keep diagnostics free of account keys, personal tokens and cloud IDs.
        let mapped = channels.map { "\($0.name) = DP \($0.dp)" }.joined(separator: ", ")
        let address = device.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !address.isEmpty else {
            surgeMessage = "Tuya reports \(channels.count) mapped switch(es), but Keystone has no confirmed local IP. Tap 'Look for them on Wi-Fi again' and retry. \(mapped)"
            return
        }
        var liveDPs: [String: JSONValue] = [:]
        var workingVersion = device.version ?? 3.3
        do {
            let (link, data) = try await LocalLink.detect(
                devId: device.id, host: address, localKey: key,
                knownDPs: Array(Set(channels.map(\.dp) + ["1", "2", "3", "4", "5", "6", "7", "8"])),
                timeout: 2, versions: [device.version ?? 3.3, 3.3, 3.4, 3.5].uniqued(),
                onDPS: { _ in }, onClose: { _ in })
            workingVersion = await link.version
            liveDPs = data
            await link.close()
        } catch {
            surgeMessage = "Keystone sees this plug at \(address), but Tuya LAN authentication/status failed: \(error.localizedDescription). This also explains 'not answering' on the generic plug. Check its local key, Wi-Fi and firmware protocol in Bridge → Power strip → Enter details by hand → Detect outlets. No changes were sent to Apple Home."
            return
        }
        let liveSwitchIDs = liveDPs.compactMap { key, value -> String? in
            if case .bool = value { return key }
            return nil
        }.sorted { (Int($0) ?? 999) < (Int($1) ?? 999) }
        guard channels.count >= 2 else {
            let detail = liveSwitchIDs.isEmpty ? "The LAN status did not expose any Boolean DPs." :
                "LAN reported Boolean DPs: \(liveSwitchIDs.joined(separator: ", "))."
            surgeMessage = "The Tuya cloud mapped only \(channels.count) individual outlet(s), so automatically adding switches could include a master switch or child lock. \(detail) Use 'Review and test DP mapping' below to identify each physical outlet. Nothing has been changed."
            return
        }
        if !liveDPs.isEmpty {
            let unverified = channels.filter { channel in
                guard let value = liveDPs[channel.dp] else { return true }
                if case .bool = value { return false }
                return true
            }
            if !unverified.isEmpty {
                surgeMessage = "LAN at \(address) answered, but the following cloud outlet IDs were absent or not Boolean in the live status: \(unverified.map(\.dp).joined(separator: ", ")). Live Boolean DPs: \(liveSwitchIDs.joined(separator: ", ")). Review and test the DP mapping below before creating any Home switches."
                return
            }
        }
        let body: [String: Any] = [
            "action": "config", "name": latest?.name ?? device.name,
            "id": device.id, "key": key, "ip": address, "ver": workingVersion,
            "outlets": channels.map { ["name": $0.name, "dp": $0.dp] }
        ]
        do {
            let reply = try await BridgeAPI.postLocal("/api/strip", body, store.link, timeout: 12)
            surgeMessage = "Keystone accepted \(channels.count) verified Tuya switch DP(s) over LAN \(address), protocol \(workingVersion). \(mapped). \(reply["restart"] as? Bool == true ? "The bridge is restarting to publish them to Home." : "Refresh Surge to load them.") Existing generic Home plug was not deleted."
            await store.refresh()
        } catch {
            surgeMessage = "The strip was verified over Tuya LAN, but Keystone rejected the new outlet configuration: \(error.localizedDescription). The original Home plug was left unchanged."
        }
    }

    private func reload() async {
        guard let t = token else { return }
        model.message = nil
        await model.refresh(t)
        if model.devices.contains(where: { $0.inHome && !$0.hasLocal }) { await model.find(model.devices.filter { $0.inHome && !$0.hasLocal }.map(\.id), link: store.link) }
    }

    @ViewBuilder private var deviceSections: some View {
        let lights = model.devices.filter(\.isLight)
        let switches = model.devices.filter(\.isSwitch)
        let purifiers = model.devices.filter(\.isPurifier)
        if model.devices.isEmpty && model.busy == nil {
            Section { Text("No lights, switches or plugs on this Smart Life account.").foregroundStyle(.secondary) }
        }
        if !lights.isEmpty { Section("Lights") { ForEach(lights) { row($0) } } }
        if !switches.isEmpty { Section("Switches and plugs") { ForEach(switches) { row($0) } } }
        if !purifiers.isEmpty {
            Section {
                ForEach(purifiers) { row($0) }
            } header: { Text("Air purifier") } footer: {
                Text("Power, auto mode, fan speed, child lock, PM2.5 and filter life, where the purifier has them. The bridge has room for one purifier; this replaces the one Exhale sent.")
            }
        }
    }

    private func row(_ d: HomeDevice) -> some View {
        let onBridge = d.isPurifier ? (store.info?.purifier?.configured == true && store.info?.purifier?.name == d.name)
                                    : store.info?.lights?.contains { $0.id == d.id } == true
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

            // Tuya's cloud-only devices cannot be bridged through a local key.
            // Their QR login can still control verified switch codes right here.
            // Keep these visibly distinct from the Apple Home membership toggle.
            if !d.cloudControlChannels.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Tuya cloud control", systemImage: "cloud")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(d.cloudControlChannels.map { $0.code }, id: \.self) { code in
                        let title = d.cloudControlChannels.first(where: { $0.code == code })?.name ?? code
                        let state = model.cloudStates[d.id]?[code]
                        let key = d.id + "/" + code
                        HStack(spacing: 8) {
                            Text(title).font(.subheadline)
                            Spacer()
                            if model.cloudPending.contains(key) {
                                ProgressView().controlSize(.small)
                            } else if let on = state {
                                Button(on ? "Turn off" : "Turn on") {
                                    Task { await setCloud(d.id, code: code, on: !on) }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!d.online || model.busy != nil)
                            } else {
                                Button("On") { Task { await setCloud(d.id, code: code, on: true) } }
                                    .buttonStyle(.bordered)
                                Button("Off") { Task { await setCloud(d.id, code: code, on: false) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .disabled(!d.online || model.cloudPending.contains(key) || model.busy != nil)
                        if let m = model.cloudMessage[key] {
                            Text(m).font(.caption2).foregroundStyle(Theme.bad).textSelection(.enabled)
                        }
                    }
                    Text("Cloud controls work with Tuya Smart authorization, not Keystone's BLE or LAN connection.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.top, 7)
            }
            if working == d.id {
                Text("Working…").font(.caption).foregroundStyle(.secondary)
            } else if d.inHome, let why = d.problem {
                Text(why).font(.caption).foregroundStyle(Theme.bad)
            } else if d.inHome {
                Text(model.syncFailure != nil
                     ? "Selected, not confirmed on the bridge"
                     : onBridge
                        ? "Configured on bridge · \(d.host ?? "")"
                        : "Selected on phone · bridge has not confirmed this device")
                    .font(.caption).foregroundStyle(model.syncFailure != nil ? Theme.bad : .secondary)
            } else if onBridge {
                Text("Already configured through \(d.isPurifier ? "Exhale" : "Afterglow")").font(.caption).foregroundStyle(.secondary)
            }
            if d.isSwitch && (d.category == "cz" || d.category == "pc" || d.name.localizedCaseInsensitiveContains("Power Outlet")) {
                Button {
                    surgeDeviceID = d.id
                    surgeMessage = nil
                    surgeCandidate = d
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "poweroutlet.strip")
                        Text("Configure individual outlets for Surge")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .disabled(working != nil || model.busy != nil)
                .padding(.top, 5)
                if surgeDeviceID == d.id, let surgeMessage {
                    Text(surgeMessage)
                        .font(.caption)
                        .foregroundStyle(surgeMessage.hasPrefix("Keystone accepted") ? .green : Theme.bad)
                        .textSelection(.enabled)
                        .padding(.vertical, 6)
                    Button {
                        UIPasteboard.general.string = surgeMessage
                        store.show("Surge diagnostic copied.")
                    } label: {
                        Label("Copy outlet diagnostic", systemImage: "doc.on.doc")
                    }
                    .font(.caption)
                }
                NavigationLink {
                    StripManualView(preset: d).environmentObject(store)
                } label: {
                    Label("Review and test DP mapping", systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
            }
        }
    }

    private func setCloud(_ id: String, code: String, on: Bool) async {
        guard let session = TuyaToken.stored ?? token else {
            model.message = "Reconnect Tuya Smart to use cloud controls."
            return
        }
        await model.cloudSwitch(id, code: code, on: on, token: session)
    }

    // MARK: Sign in (same Smart Life login as the power strip)

    @ViewBuilder private var loginSection: some View {
        Section {
            if let qrImage, qr != nil {
                Text("Scan this in Tuya Smart").font(.headline)
                Image(uiImage: qrImage).interpolation(.none).resizable().scaledToFit()
                    .padding(12).background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 260).frame(maxWidth: .infinity)
                ShareLink(item: Image(uiImage: qrImage), preview: SharePreview("Tuya Smart login", image: Image(uiImage: qrImage))) {
                    Label("Share or save the QR", systemImage: "square.and.arrow.up")
                }
                Button { TuyaSmartApp.open() } label: {
                    Label("Open Tuya Smart", systemImage: "arrow.up.forward.app")
                }
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to confirm in Tuya Smart…").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Start over") { pollTask?.cancel(); qr = nil; self.qrImage = nil }.font(.footnote)
                }
            } else {
                TextField("Tuya Smart user code", text: $userCode)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Button { Task { await getQR() } } label: {
                    HStack { Text("Get login QR"); Spacer(); if working == "qr" { ProgressView() } }
                }
                .disabled(working != nil || userCode.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: { Text("Sign in to Tuya Smart") } footer: {
            Text(qr == nil
                 ? "Once. In Tuya Smart: Me › ⚙︎ Settings › Account and Security › User Code. Paste it, get the QR, then in Tuya Smart tap + › Scan and confirm. Keystone reads your devices' names, IDs and local keys."
                 : "On this phone: share the QR and save it to Photos, open Tuya Smart, tap + › Scan, tap the photo icon and pick it. Confirm and come back.")
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
                        token = got; qr = nil; qrImage = nil; reconnecting = false
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

private extension Array where Element: Equatable {
    func uniqued() -> [Element] {
        var result: [Element] = []
        for item in self where !result.contains(item) { result.append(item) }
        return result
    }
}
