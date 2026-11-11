import SwiftUI

/// Sets up a Tuya / Smart Life Wi-Fi power strip on the bridge. Each outlet becomes its own Outlet tile in
/// Apple Home and a toggle on Keystone's home screen. Setup goes over the home Wi-Fi only (the key travels).
struct StripSetupView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    struct Row: Identifiable, Equatable { let id = UUID(); var name: String; var dp: String }

    @State private var name = "Power Strip"
    @State private var devId = ""
    @State private var key = ""
    @State private var ip = ""
    @State private var ver = 3.3
    @State private var rows: [Row] = [Row(name: "Outlet 1", dp: "1"), Row(name: "Outlet 2", dp: "2"),
                                     Row(name: "Outlet 3", dp: "3"), Row(name: "USB", dp: "7")]
    @State private var probe: String?
    @State private var busy = false
    @State private var loaded = false
    @State private var confirmRemove = false

    private var existing: BridgeInfo.Strip? { store.info?.strip?.configured == true ? store.info?.strip : nil }
    private var keyOK: Bool { key.count == 16 || (key.isEmpty && existing != nil && existing?.id == devId) }
    private var canSave: Bool {
        !devId.trimmed.isEmpty && !ip.trimmed.isEmpty && keyOK && rows.contains { !$0.dp.trimmed.isEmpty } && !busy
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Device ID", text: $devId).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(existing != nil ? "Local key (blank = keep)" : "Local key (16 characters)", text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("IP address", text: $ip).keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                Picker("Protocol", selection: $ver) {
                    Text("3.3").tag(3.3); Text("3.4").tag(3.4); Text("3.5").tag(3.5)
                }
            } header: { Text("Strip") } footer: {
                Text("Same details your other Tuya apps use: device ID and local key from the Smart Life account, and the strip's IP on your Wi-Fi (give it a DHCP reservation in the router so it doesn't move).")
            }

            Section {
                Button(busy ? "Asking the strip…" : "Detect outlets") { Task { await detect() } }
                    .disabled(busy || devId.trimmed.isEmpty || ip.trimmed.isEmpty || !keyOK)
                if let probe { Text(probe).font(.caption.monospaced()).textSelection(.enabled) }
            } footer: {
                Text("Reads the strip's status through the bridge. On/off values (true/false) are the outlets: flip one in Smart Life and detect again to see which number moves.")
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
                Text("Each row is one tile in Apple Home. Name them after what's plugged in. Typical strips use DP 1–3 for the outlets and 7 for USB.")
            }

            Section {
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
        .navigationTitle("Power strip")
        .onAppear(perform: load)
        .confirmationDialog("Remove the power strip from the bridge and Apple Home?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await remove() } }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let s = existing else { return }
        name = s.name ?? name
        devId = s.id ?? ""
        ip = s.ip ?? ""
        ver = s.ver ?? 3.3
        if let o = s.outlets, !o.isEmpty { rows = o.map { Row(name: $0.name, dp: $0.dp) } }
    }

    private var creds: [String: Any] {
        ["id": devId.trimmed, "key": key.trimmed, "ip": ip.trimmed, "ver": ver]
    }

    private func detect() async {
        busy = true
        defer { busy = false }
        do {
            var body = creds
            body["action"] = "probe"
            let r = try await BridgeAPI.post("/api/strip", body, store.link, timeout: 10)
            guard r["ok"] as? Bool == true, let dps = r["dps"] as? [String: Any] else {
                probe = "No answer: \(r["error"] as? String ?? "unknown"). Check the IP, key and protocol."
                return
            }
            let keys = dps.keys.sorted { (Int($0) ?? 999) < (Int($1) ?? 999) }
            probe = keys.map { k in "DP \(k): \(isBool(dps[k]) ? ((dps[k] as? Bool) == true ? "true" : "false") : String(describing: dps[k] ?? ""))" }.joined(separator: "\n")
            let switches = keys.filter { isBool(dps[$0]) && (Int($0) ?? 0) < 20 }
            if !switches.isEmpty, existing == nil {
                rows = switches.enumerated().map { i, dp in
                    Row(name: i == switches.count - 1 && switches.count > 3 ? "USB" : "Outlet \(i + 1)", dp: dp)
                }
            }
        } catch {
            probe = "Couldn't reach the bridge on your Wi-Fi: \(error.localizedDescription)"
        }
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
            let r = try await BridgeAPI.post("/api/strip", body, store.link, timeout: 10)
            store.show((r["restart"] as? Bool) == true ? "Saved. The bridge is restarting so Home gets the outlets." : "Saved.")
            await store.refresh()
            dismiss()
        } catch {
            store.show("Setup needs your home Wi-Fi: \(error.localizedDescription)")
        }
    }

    private func remove() async {
        do {
            try await BridgeAPI.post("/api/strip", ["action": "remove"], store.link, timeout: 10)
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
