import AppIntents

struct SceneEntity: AppEntity, Identifiable {
    var id: UUID
    var name: String
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Keystone scene"
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = SceneQuery()
}

struct SceneQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SceneEntity] {
        KScene.stored.filter { identifiers.contains($0.id) }.map { SceneEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [SceneEntity] {
        KScene.stored.map { SceneEntity(id: $0.id, name: $0.name) }
    }
}

struct RunSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Keystone Scene"
    static var description = IntentDescription("Sets the lights, TV, sound bar, purifier and AC the way the scene says. Works away from home too.")
    @Parameter(title: "Scene") var scene: SceneEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = KScene.stored.first(where: { $0.id == scene.id }) else {
            return .result(dialog: "That scene is gone.")
        }
        let failed = await KScene.run(s)
        return .result(dialog: failed.isEmpty ? "\(s.name) is set." : "\(s.name): couldn't do \(failed.joined(separator: ", ")).")
    }
}

struct KeystoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunSceneIntent(),
                    phrases: ["Run \(\.$scene) in \(.applicationName)",
                              "\(\.$scene) in \(.applicationName)",
                              "Set \(\.$scene) with \(.applicationName)"],
                    shortTitle: "Run scene",
                    systemImageName: "sparkles")
    }
}
