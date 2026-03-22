import SwiftUI
import ServiceManagement

@main
struct MagicTrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var trackpadManager = TrackpadManager.shared
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var appSwitcherManager = AppSwitcherManager.shared
    @AppStorage(AppVisibilityManager.showMenuBarIconKey) private var showMenuBarIcon = true

    var body: some Scene {
        // 메인 윈도우 (Settings-style)
        WindowGroup("MagicTrack") {
            MainView()
                .environmentObject(trackpadManager)
                .environmentObject(presetManager)
                .environmentObject(appSwitcherManager)
                .frame(minWidth: 500, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .commands {
            // 기본 메뉴 제거
            CommandGroup(replacing: .newItem) {}
            CommandMenu("트랙패드") {
                Button("내장/매직 전환") {
                    trackpadManager.toggleSelectedTrackpad()
                }
                .keyboardShortcut("m", modifiers: [.option])
            }
        }

        MenuBarExtra("MagicTrack", systemImage: "rectangle.roundedtop.fill", isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(trackpadManager)
                .environmentObject(presetManager)
        }
        .menuBarExtraStyle(.window)

        // 환경설정
        Settings {
            SettingsView()
                .environmentObject(trackpadManager)
                .environmentObject(presetManager)
                .environmentObject(appSwitcherManager)
        }
    }

}
