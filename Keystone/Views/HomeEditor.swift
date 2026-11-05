import SwiftUI

enum HomeCard: String, CaseIterable, Codable, Identifiable {
    case scenes, climate, ac, camera, purifier, tv, lights, bar, ir, activity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .scenes: return "Scenes"
        case .climate: return "Room and air"
        case .ac: return "AC"
        case .camera: return "Camera"
        case .purifier: return "Purifier"
        case .tv: return "TV"
        case .lights: return "Lights"
        case .bar: return "Sound bar"
        case .ir: return "IR remotes"
        case .activity: return "Activity"
        }
    }

    var icon: String {
        switch self {
        case .scenes: return "sparkles"
        case .climate: return "thermometer.medium"
        case .ac: return "air.conditioner.horizontal"
        case .camera: return "video"
        case .purifier: return "wind"
        case .tv: return "tv"
        case .lights: return "lightbulb"
        case .bar: return "hifispeaker"
        case .ir: return "dot.radiowaves.right"
        case .activity: return "list.bullet"
        }
    }
}

/// How the home screen is laid out on this phone: card order, hidden cards, and per-light order,
/// hiding and names. New cards and new lights from the bridge show up on their own, at the end.
@MainActor
final class HomeLayout: ObservableObject {
    static let shared = HomeLayout()

    struct Saved: Codable {
        var order: [HomeCard] = HomeCard.allCases
        var hidden: Set<HomeCard> = []
        var lightOrder: [String] = []
        var hiddenLights: Set<String> = []
        var lightNames: [String: String] = [:]
    }

    @Published var saved: Saved { didSet { persist() } }

    private init() {
        if let d = UserDefaults.standard.data(forKey: "homeLayout"), let s = try? JSONDecoder().decode(Saved.self, from: d) {
            saved = s
        } else {
            saved = Saved()
        }
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: "homeLayout")
    }

    /// Saved order first, then any card type added since.
    func ordered(_ available: [HomeCard]) -> [HomeCard] {
        saved.order.filter(available.contains) + available.filter { !saved.order.contains($0) }
    }

    func visible(_ available: [HomeCard]) -> [HomeCard] {
        ordered(available).filter { !saved.hidden.contains($0) }
    }

    struct LightItem { let light: BridgeInfo.Light; let idx: Int }

    /// Visible lights in the user's order, each with the bridge's index for controlling it.
    func orderedLights(_ lights: [BridgeInfo.Light], includeHidden: Bool = false) -> [LightItem] {
        let items = lights.enumerated().map { LightItem(light: $0.element, idx: $0.offset) }
        let known = saved.lightOrder.compactMap { id in items.first { $0.light.id == id } }
        let rest = items.filter { !saved.lightOrder.contains($0.light.id) }
        return (known + rest).filter { includeHidden || !saved.hiddenLights.contains($0.light.id) }
    }

    func name(for l: BridgeInfo.Light) -> String {
        let n = saved.lightNames[l.id]?.trimmingCharacters(in: .whitespaces) ?? ""
        return n.isEmpty ? l.name : n
    }
}

struct HomeEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var layout = HomeLayout.shared
    let available: [HomeCard]
    let lights: [BridgeInfo.Light]

    @State private var cards: [HomeCard] = []
    @State private var lightIDs: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(cards) { c in
                        Toggle(isOn: Binding(
                            get: { !layout.saved.hidden.contains(c) },
                            set: { v in if v { layout.saved.hidden.remove(c) } else { layout.saved.hidden.insert(c) } })) {
                            Label(c.title, systemImage: c.icon)
                        }
                    }
                    .onMove { from, to in
                        cards.move(fromOffsets: from, toOffset: to)
                        layout.saved.order = cards + layout.saved.order.filter { !cards.contains($0) }
                    }
                } header: {
                    Text("Cards")
                } footer: {
                    Text("Drag to reorder, switch off to hide. New devices added to the bridge show up at the bottom.")
                }

                if !lights.isEmpty {
                    Section {
                        ForEach(lightIDs, id: \.self) { id in
                            if let l = lights.first(where: { $0.id == id }) {
                                HStack {
                                    TextField(l.name, text: Binding(
                                        get: { layout.saved.lightNames[id] ?? "" },
                                        set: { layout.saved.lightNames[id] = $0 }))
                                    Toggle("", isOn: Binding(
                                        get: { !layout.saved.hiddenLights.contains(id) },
                                        set: { v in if v { layout.saved.hiddenLights.remove(id) } else { layout.saved.hiddenLights.insert(id) } }))
                                        .labelsHidden()
                                }
                            }
                        }
                        .onMove { from, to in
                            lightIDs.move(fromOffsets: from, toOffset: to)
                            layout.saved.lightOrder = lightIDs
                        }
                    } header: {
                        Text("Lights")
                    } footer: {
                        Text("Rename, reorder or hide lights on this screen. Names here only change Keystone.")
                    }
                }

                Section {
                    Button {
                        if let u = URL(string: "afterglow://sync") { openURL(u) }
                    } label: {
                        Label("Add or update lights", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh from the bridge", systemImage: "arrow.clockwise")
                    }
                } header: {
                    Text("Devices")
                } footer: {
                    Text("Lights come from Afterglow. \"Add or update lights\" opens it to pick up switches and lights added in Smart Life and send them to the bridge. Do this at home; the bridge only takes new devices over your Wi-Fi.")
                }

                Section {
                    Button("Reset layout", role: .destructive) {
                        layout.saved = .init()
                        load()
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        cards = layout.ordered(available)
        lightIDs = layout.orderedLights(lights, includeHidden: true).map(\.light.id)
    }
}
