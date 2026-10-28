import SwiftUI

struct PairView: View {
    @EnvironmentObject var store: Store
    @StateObject private var finder = BridgeFinder()
    @State private var manual = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "cpu.fill").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.yellow)
                        Text("Keystone").font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("Control panel for your home bridge: its screen, firmware and everything it puts in Apple Home.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Bridges on your Wi-Fi").font(.headline)
                            Spacer()
                            if finder.searching { ProgressView() } else {
                                Button("Search") { finder.start() }.font(.subheadline)
                            }
                        }
                        if finder.found.isEmpty && !finder.searching {
                            Text("None found. Make sure you're on the same Wi-Fi as the bridge and that Keystone has Local Network access (Settings › Privacy › Local Network). A VPN can hide it too.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(finder.found, id: \.self) { f in
                            Button { Task { await pair(f.host, f.port) } } label: {
                                HStack {
                                    Image(systemName: "cpu").foregroundStyle(Theme.blue)
                                    VStack(alignment: .leading) {
                                        Text(f.name).fontWeight(.semibold)
                                        Text(f.host).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if busy { ProgressView() } else { Text("Pair").foregroundStyle(Theme.yellow) }
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .disabled(busy)
                        }
                        HStack {
                            TextField("Or type its IP (on its screen)", text: $manual)
                                .keyboardType(.decimalPad)
                                .padding(12)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            Button("Pair") { Task { await pair(manual.trimmingCharacters(in: .whitespaces), 8080) } }
                                .disabled(manual.isEmpty || busy)
                        }
                    }
                    .card()

                    if let error {
                        Text(error).font(.footnote).foregroundStyle(Theme.bad).card()
                    }

                    Text("No bridge yet? Set one up from Afterglow › Settings › Apple Home bridge.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
            }
        }
        .onAppear { finder.start() }
        .onDisappear { finder.stop() }
    }

    private func pair(_ host: String, _ port: Int) async {
        guard !host.isEmpty else { return }
        busy = true
        error = nil
        defer { busy = false }
        do { try await store.pair(host: host, port: port) } catch { self.error = error.localizedDescription }
    }
}
