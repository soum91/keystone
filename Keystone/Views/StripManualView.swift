import SwiftUI
import UIKit

/// Manual fallback for the power strip: type the device ID, local key and IP yourself. The normal path is StripSetupView. Each outlet becomes its own Outlet tile in
/// Apple Home and a toggle on Keystone's home screen. Setup goes over the home Wi-Fi only (the key travels).
struct StripManualView: View {
    private let preset: HomeDevice?
    init(preset: HomeDevice? = nil) { self.preset = preset }
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable, Equatable { let id = UUID(); var name: String; var dp: String }

    @State private var name = "Power Strip"
    @State private var devId = ""
    @State private var key = ""
    @State private var ip = ""
    @State private var ver = 3.3
    @State private var rows: [Row] = []
    @State private var lastBooleanStates: [String: Bool] = [:]
    @State private var changedDataPoints: [String] = []
    @State private var detectedDataPoints: [String] = []
    @State private var confirmedMapping = false
    @State private var probe: String?
    @State private var busy = false
    @State private var loaded = false
    @State private var confirmRemove = false

    private var existing: BridgeInfo.Strip? { store.info?.strip?.configured == true ? store.info?.strip : nil }
    private var keyOK: Bool { key.count == 16 || (key.isEmpty && existing != nil && existing?.id == devId) }
    private var canSave: Bool {
        !devId.trimmed.isEmpty && keyOK && rows.contains { !$0.dp.trimmed.isEmpty } && !busy && (existing != nil || confirmedMapping)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Device ID", text: $devId).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(existing != nil ? "Local key (blank = keep)" : "Local key (16 characters)", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("IP address (blank = let the bridge find it)", text: $ip).keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                Picker("Protocol", selection: $ver) {
                    Text("3.3").tag(3.3); Text("3.4").tag(3.4); Text("3.5").tag(3.5)
                }
            } header: { Text("Strip") } footer: {
                Text("Same details your other Tuya apps use: device ID and local key from the Smart Life account, and the strip's IP on your Wi-Fi (give it a DHCP reservation in the router so it doesn't move).")
            }

            Section {
                Button(busy ? "Asking the strip…" : "Detect outlets") { Task { await detect() } }
                    .disabled(busy || devId.trimmed.isEmpty || ip.trimmed.isEmpty || !keyOK)
                if let probe {
                    Text(probe).font(.caption.monospaced()).textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = probe
                        store.show("Read-only Tuya DP report copied.")
                    } label: { Label("Copy DP report", systemImage: "doc.on.doc") }
                }
                if !changedDataPoints.isEmpty {
                    Text("These values changed since the last scan. Select only the one you physically switched:")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(changedDataPoints, id: \.self) { dp in
                        Button("Add changed DP \(dp)") {
                            if !rows.contains(where: { $0.dp == dp }) {
                                rows.append(Row(name: "Outlet \(rows.count + 1)", dp: dp))
                            }
                        }
                    }
                }
                Button { TuyaSmartApp.open() } label: {
                    Label("Open Tuya Smart to toggle one outlet", systemImage: "arrow.up.forward.app")
                }
            } footer: {
                Text("Read-only: first detect, toggle exactly ONE outlet in Tuya Smart, then detect again. The changed DP identifies that control. Not every Boolean DP is an outlet: master power and child lock may also appear.")
            }

            Section {
                ForEach($rows) { $r in
                    HStack {
                        TextField("Name in Home", text: $r.name)
                        TextField("DP", text: $r.dp).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 50)
                    }
                }
                .onDelete { rows.remove(atOffsets: $0) }
                if rows.count < 6 { Button("Add outlet") { rows.append(Row(name: "Outlet \(rows.count + 1)", dp: "")) } }
            } header: { Text("Outlets") } footer: {
                Text("Each row is an Apple Home outlet. Add only DPs you have confirmed by flipping one actual socket at a time. Do not include master power, child lock, or other Boolean settings.")
            }

            Section {
                if existing == nil {
                    Toggle("I verified these DP numbers correspond to individual sockets", isOn: $confirmedMapping)
                }
                Button(existing == nil ? "Add to the bridge" : "Save") { Task { await save() } }.disabled(!canSave)
                if existing != nil {
                    Button("Remove the power strip", role: .destructive) { confirmRemove = true }
                }
            } footer: {
                Text("New or renamed outlets restart the bridge (about 20 s) so Apple Home picks them up.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Enter by hand")
        .onAppear(perform: load)
        .task {
            // A device re-pair changes its local key. Refresh it without asking the user
            // to copy credentials; keep the previously saved key when offline.
            guard let preset, let token = TuyaToken.stored else { return }
            let client = TuyaClient(token: token)
            if let latest = try? await client.device(id: preset.id),
               let freshKey = latest.localKey, freshKey.count == 16 {
                key = freshKey
            }
        }
        .confirmationDialog("Remove the power strip from the bridge and Apple Home?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await remove() } }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let s = existing {
            name = s.name ?? name
            devId = s.id ?? ""
            ip = s.ip ?? ""
            ver = s.ver ?? 3.3
            if let o = s.outlets, !o.isEmpty { rows = o.map { Row(name: $0.name, dp: $0.dp) } }
            return
        }
        guard let preset else { return }
        name = preset.name
        devId = preset.id
        key = preset.localKey ?? ""
        ip = preset.host ?? ""
        ver = preset.version ?? 3.3
        rows = TuyaClient.stripOutlets(from: preset.dpMap).map { Row(name: $0.name, dp: $0.dp) }
    }

    private var creds: [String: Any] {
        ["id": devId.trimmed, "key": key.trimmed, "ip": ip.trimmed, "ver": ver]
    }

    private func detect() async {
        busy = true
        defer { busy = false }
        var versions = [ver]
        for candidate in [3.3, 3.4, 3.5] where !versions.contains(candidate) { versions.append(candidate) }
        var errors: [String] = []
        for candidate in versions {
            var body = creds
            body["action"] = "probe"
            body["ver"] = candidate
            do {
                let reply = try await BridgeAPI.postLocal("/api/strip", body, store.link, timeout: 10)
                guard let dps = reply["dps"] as? [String: Any] else {
                    errors.append("\(candidate): device returned no DP status")
                    continue
                }
                ver = candidate
                let keys = dps.keys.sorted { (Int($0) ?? 999) < (Int($1) ?? 999) }
                probe = "Tuya LAN protocol \(candidate) confirmed\n" +
                    keys.map { key in
                        "DP \(key): \(isBool(dps[key]) ? ((dps[key] as? Bool) == true ? "true" : "false") : String(describing: dps[key] ?? ""))"
                    }.joined(separator: "\n")
                let states: [String: Bool] = dps.reduce(into: [:]) { values, item in
                    if isBool(item.value), let state = item.value as? Bool {
                        values[item.key] = state
                    }
                }
                detectedDataPoints = states.keys.sorted { (Int($0) ?? 999) < (Int($1) ?? 999) }
                changedDataPoints = states.keys.filter {
                    guard let before = lastBooleanStates[$0] else { return false }
                    return before != states[$0]
                }.sorted { (Int($0) ?? 999) < (Int($1) ?? 999) }
                lastBooleanStates = states
                if !changedDataPoints.isEmpty {
                    probe = "Changed Boolean DP(s): \(changedDataPoints.joined(separator: ", "))\n" + (probe ?? "")
                }
                return
            } catch {
                errors.append("\(candidate): \(error.localizedDescription)")
            }
        }
        probe = "No authenticated Tuya LAN status at \(ip.trimmed) for protocols 3.3/3.4/3.5.\n" +
            errors.joined(separator: "\n") +
            "\nNo outlet was added. Confirm the private strip IP and a current 16-character local key in Tuya Smart."
    }

    /// JSONSerialization hands back NSNumber for both; only a real boolean is an outlet.
    private func isBool(_ v: Any?) -> Bool {
        guard let n = v as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    private func save() async {
        busy = true
        defer { busy = false }
        var body = creds
        body["action"] = "config"
        body["name"] = name.trimmed.isEmpty ? "Power Strip" : name.trimmed
        body["outlets"] = rows.filter { !$0.dp.trimmed.isEmpty }.map { ["name": $0.name.trimmed, "dp": $0.dp.trimmed] }
        do {
            let r = try await BridgeAPI.postLocal("/api/strip", body, store.link, timeout: 10)
            store.show((r["restart"] as? Bool) == true ? "Saved. The bridge is restarting so Home gets the outlets." : "Saved.")
            await store.refresh()
            dismiss()
        } catch {
            store.show("Setup needs your home Wi-Fi: \(error.localizedDescription)")
        }
    }

    private func remove() async {
        do {
            try await BridgeAPI.postLocal("/api/strip", ["action": "remove"], store.link, timeout: 10)
            store.show("Power strip removed. The bridge is restarting.")
            await store.refresh()
            dismiss()
        } catch {
            store.show(error.localizedDescription)
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
