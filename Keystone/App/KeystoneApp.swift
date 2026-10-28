import SwiftUI

@main
struct KeystoneApp: App {
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.yellow)
        }
        .onChange(of: phase, initial: true) { _, p in
            switch p {
            case .active: store.startPolling()
            case .background: store.stopPolling()
            default: break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ZStack(alignment: .bottom) {
            if store.isPaired {
                TabView {
                    DashboardView().tabItem { Label("Home", systemImage: "square.grid.2x2.fill") }
                    DisplayView().tabItem { Label("Display", systemImage: "rectangle.inset.filled") }
                    BridgeView().tabItem { Label("Bridge", systemImage: "cpu") }
                }
            } else {
                PairView()
            }
            if let t = store.toast {
                Text(t)
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { store.toast = nil }
            }
        }
        .animation(.spring(duration: 0.3), value: store.toast)
        .animation(.easeInOut, value: store.isPaired)
    }
}
