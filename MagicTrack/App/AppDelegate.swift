import AppKit
import ServiceManagement
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppVisibilityManager.shared.applyCurrentDockPreference()

        // 트랙패드 모니터링 시작
        TrackpadManager.shared.startMonitoring()

        // 앱 전환 감지 시작
        AppSwitcherManager.shared.startMonitoring()

        // 전역 단축키 등록
        HotKeyManager.shared.registerToggleTrackpadHotKey()

        // 로그인 시 자동 시작 등록
        registerLoginItem()

        // 권한 확인
        PermissionManager.shared.checkPermissions()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDockVisibilityChanged),
            name: .dockVisibilityChanged,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        HotKeyManager.shared.unregisterToggleTrackpadHotKey()
        TrackpadManager.shared.stopMonitoring()
        AppSwitcherManager.shared.stopMonitoring()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // 메뉴바 앱에서 Dock 아이콘 클릭 시 메인 창 열기
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private func registerLoginItem() {
        // macOS 13+ SMAppService 사용
        if #available(macOS 13.0, *) {
            // 사용자 설정에 따라 자동 시작 등록
            let launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
            if launchAtLogin {
                try? SMAppService.mainApp.register()
            }
        }
    }

    @objc private func handleDockVisibilityChanged() {
        AppVisibilityManager.shared.applyCurrentDockPreference(activateIfNeeded: true)
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4D54524B), id: 1)

    private init() {}

    func registerToggleTrackpadHotKey() {
        unregisterToggleTrackpadHotKey()

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let eventRef, let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyEvent(eventRef)
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregisterToggleTrackpadHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func handleHotKeyEvent(_ eventRef: EventRef) -> OSStatus {
        var pressedHotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &pressedHotKeyID
        )

        guard status == noErr else { return status }
        guard pressedHotKeyID.signature == hotKeyID.signature, pressedHotKeyID.id == hotKeyID.id else {
            return noErr
        }

        TrackpadManager.shared.toggleSelectedTrackpad()
        return noErr
    }
}

extension Notification.Name {
    static let dockVisibilityChanged = Notification.Name("dockVisibilityChanged")
}

enum AppInfo {
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionDescription: String {
        "버전 \(shortVersion) (\(buildNumber))"
    }

    static var compactVersionDescription: String {
        "v\(shortVersion)"
    }
}

final class AppVisibilityManager {
    static let shared = AppVisibilityManager()
    static let showDockIconKey = "showDockIcon"
    static let showMenuBarIconKey = "showMenuBarIcon"

    private init() {}

    var showsDockIcon: Bool {
        if let storedValue = UserDefaults.standard.object(forKey: Self.showDockIconKey) as? Bool {
            return storedValue
        }
        return true
    }

    var showsMenuBarIcon: Bool {
        if let storedValue = UserDefaults.standard.object(forKey: Self.showMenuBarIconKey) as? Bool {
            return storedValue
        }
        return true
    }

    func ensureAtLeastOneVisible(changedKey: String? = nil) {
        var dockVisible = showsDockIcon
        var menuBarVisible = showsMenuBarIcon

        guard !dockVisible && !menuBarVisible else { return }

        if changedKey == Self.showDockIconKey {
            menuBarVisible = true
            UserDefaults.standard.set(true, forKey: Self.showMenuBarIconKey)
        } else {
            dockVisible = true
            UserDefaults.standard.set(true, forKey: Self.showDockIconKey)
        }
    }

    func applyCurrentDockPreference(activateIfNeeded: Bool = false) {
        ensureAtLeastOneVisible()
        let desiredPolicy: NSApplication.ActivationPolicy = showsDockIcon ? .regular : .accessory

        if NSApp.activationPolicy() != desiredPolicy {
            NSApp.setActivationPolicy(desiredPolicy)
        }

        if activateIfNeeded {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
