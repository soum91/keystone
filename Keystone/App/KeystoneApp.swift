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
    @State private var selectedTab = 0
    @State private var showStripSetup = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if store.isPaired {
                TabView(selection: $selectedTab) {
                    DashboardView().tabItem { Label("Home", systemImage: "square.grid.2x2.fill") }.tag(0)
                    DisplayView().tabItem { Label("Display", systemImage: "rectangle.inset.filled") }.tag(1)
                    RouterTab().tabItem { Label("Router", systemImage: "wifi.router") }.tag(2)
                    BridgeView(showStripSetup: $showStripSetup).tabItem { Label("Bridge", systemImage: "cpu") }.tag(3)
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
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "keystone", url.host == "power-strip" else { return }
            selectedTab = 3
            showStripSetup = true
        }
    }
}
