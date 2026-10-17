import AppKit
import SwiftUI

var isRunningUnitTests: Bool {
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

struct ContentView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSession.self) private var session

    var body: some View {
        if isRunningUnitTests {
            Color.clear.frame(width: 1, height: 1)
        } else {
            @Bindable var router = router
            TabView(selection: $router.selectedTab) {
                tab(.overview) { OverviewView() }
                    .tabItem { Label("Overview", systemImage: "waveform.path.ecg") }
                    .tag(AppTab.overview)
                tab(.apps) { AppsView() }
                    .tabItem { Label("Apps", systemImage: "square.grid.2x2") }
                    .tag(AppTab.apps)
                tab(.energy) { EnergyView() }
                    .tabItem { Label("Energy", systemImage: "bolt") }
                    .tag(AppTab.energy)
                tab(.history) { HistoryView() }
                    .tabItem { Label("History", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(AppTab.history)
                tab(.wiki) { WikiView() }
                    .tabItem { Label("Wiki", systemImage: "book.closed") }
                    .tag(AppTab.wiki)
                tab(.advanced) { AdvancedView() }
                    .tabItem { Label("Advanced", systemImage: "list.bullet.rectangle") }
                    .tag(AppTab.advanced)
                tab(.settings) { SettingsView() }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .tint(Palette.accent)
            .frame(minWidth: 720, minHeight: 480)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        if session.isReadHeld && !session.isPaused {
                            Text("Holding")
                                .font(Typeface.label(10))
                                .foregroundStyle(Palette.inkSoft.opacity(0.75))
                                .help("Updates hold while you read a name or keep a card open")
                        }
                        PauseButton()
                    }
                }
            }
            .onAppear {
                NSApp.activate(ignoringOtherApps: true)
            }
            .background { WindowVisibilityObserver { session.setWindowVisible($0) } }
        }
    }

    /// Only the selected tab is kept in the hierarchy. A hidden tab would
    /// otherwise stay subscribed to the session and re-render on every sample,
    /// and hold onto its view tree for the life of the window.
    @ViewBuilder
    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        if router.selectedTab == tab {
            content()
        } else {
            Color.clear
        }
    }
}

@main
struct WrenApp: App {
    @State private var preferences = AppPreferences()
    @State private var session: AppSession
    @State private var router = AppRouter()

    init() {
        let preferences = AppPreferences()
        let session = AppSession(preferences: preferences)
        _preferences = State(initialValue: preferences)
        _session = State(initialValue: session)
        if !isRunningUnitTests {
            session.start()
        }
    }

    var body: some Scene {
        WindowGroup("Wren", id: "main") {
            ContentView()
                .environment(session)
                .environment(preferences)
                .environment(router)
        }
        .defaultSize(width: 920, height: 640)

        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarContent()
                .environment(session)
                .environment(preferences)
                .environment(router)
        } label: {
            MenuBarLabel(session: session, preferences: preferences)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { isRunningUnitTests ? false : preferences.showsMenuBarExtra },
            set: { newValue in
                if !isRunningUnitTests { preferences.showsMenuBarExtra = newValue }
            }
        )
    }
}
