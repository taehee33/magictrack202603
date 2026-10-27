import SwiftUI
import ServiceManagement

@main
struct MagicTrackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var trackpadManager = TrackpadManager.shared
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var appSwitcherManager = AppSwitcherManager.shared
    @StateObject private var hotKeys = HotKeyManager.shared
    @AppStorage(AppVisibilityManager.showMenuBarIconKey) private var showMenuBarIcon = true

    var body: some Scene {
        // 메인 윈도우 (Settings-style)
        WindowGroup(AppInfo.name, id: "MagicTrack") {
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
            // 별도 설정 창 대신 메인 창의 설정 탭을 연다
            CommandGroup(replacing: .appSettings) {
                OpenSettingsTabButton()
            }
            CommandMenu("트랙패드") {
                // 단축키는 HotKeyManager의 전역 단축키가 처리한다. 여기에도 단축키를 걸면 앱이 앞에 있을 때 두 번 전환됨
                Button(hotKeys.activeDisplayString.map { "전환 모드 바꾸기 (\($0))" } ?? "전환 모드 바꾸기") {
                    trackpadManager.toggleSelectedTrackpad()
                }
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(trackpadManager)
                .environmentObject(presetManager)
        } label: {
            // 지금 적용 중인 트랙패드가 채워진 아이콘
            Image(nsImage: MenuBarIcon.image(active: trackpadManager.activeTrackpadType))
        }
        .menuBarExtraStyle(.window)
    }

}

private struct OpenSettingsTabButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("설정…") {
            AppVisibilityManager.shared.applyCurrentDockPreference()
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("MagicTrack") == true }) {
                window.makeKeyAndOrderFront(nil)
                NotificationCenter.default.post(name: .showSettingsTab, object: nil)
            } else {
                MainView.opensSettingsOnAppear = true
                openWindow(id: "MagicTrack")
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
    }
}
