import AppIntents
import Foundation

enum SocketAction: String, AppEnum {
    case on, off, toggle
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Power"
    static var caseDisplayRepresentations: [SocketAction: DisplayRepresentation] = [
        .on: "On", .off: "Off", .toggle: "Toggle"
    ]
}

struct SocketEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Socket"
    static var defaultQuery = SocketQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct SocketQuery: EntityQuery {
    func entities(for identifiers: [SocketEntity.ID]) async throws -> [SocketEntity] {
        SocketCache.read().filter { identifiers.contains($0.id) }
            .map { SocketEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [SocketEntity] {
        SocketCache.read().map { SocketEntity(id: $0.id, name: $0.name) }
    }
}

struct ControlSocketIntent: AppIntent {
    static var title: LocalizedStringResource = "Control Socket"
    static var description = IntentDescription("Turn on, turn off or toggle one Keystone power strip socket.")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Socket") var socket: SocketEntity
    @Parameter(title: "Action", default: .toggle) var action: SocketAction
    func perform() async throws -> some IntentResult {
        try await SocketStore.shared.control(id: socket.id, action: action)
        return .result()
    }
}

enum AllSocketsAction: String, AppEnum {
    case on, off
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Power"
    static var caseDisplayRepresentations: [AllSocketsAction: DisplayRepresentation] = [
        .on: "On", .off: "Off"
    ]
}

struct AllSocketsIntent: AppIntent {
    static var title: LocalizedStringResource = "Set All Sockets"
    static var description = IntentDescription("Turn all sockets on, or all except Keystone off.")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Action", default: .off) var action: AllSocketsAction
    func perform() async throws -> some IntentResult {
        try await SocketStore.shared.all(action == .on)
        return .result()
    }
}

struct SocketShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(intent: ControlSocketIntent(),
                        phrases: ["Control a socket using \(.applicationName)",
                                  "Switch an outlet using \(.applicationName)"],
                        shortTitle: "Control Socket", systemImageName: "poweroutlet.type.b"),
            AppShortcut(intent: AllSocketsIntent(),
                        phrases: ["Set all sockets using \(.applicationName)",
                                  "Switch all sockets using \(.applicationName)"],
                        shortTitle: "Set All Sockets", systemImageName: "poweroutlet.strip")
        ]
    }
}
