import AppKit
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppTheme.selected.apply()
        AppVisibilityManager.shared.applyCurrentDockPreference()

        // 트랙패드 모니터링 시작
        TrackpadManager.shared.startMonitoring()

        // 매직 트랙패드 배터리 잔량·부족 알림
        BatteryMonitor.shared.start()

        // 앱 전환 감지 시작
        AppSwitcherManager.shared.startMonitoring()

        // 전역 단축키 등록
        HotKeyManager.shared.registerToggleTrackpadHotKey()

        // 권한 확인
        PermissionManager.shared.checkPermissions()

        // 새 버전 확인 (자동 확인이 켜져 있을 때 하루 한 번)
        UpdateChecker.shared.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDockVisibilityChanged),
            name: .dockVisibilityChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        HotKeyManager.shared.unregisterToggleTrackpadHotKey()
        BatteryMonitor.shared.stop()
        TrackpadManager.shared.stopMonitoring()
        AppSwitcherManager.shared.stopMonitoring()
    }

    /// Dock에서 '종료'를 누르면 끄지 않고 Dock 아이콘만 숨긴 채 메뉴바에서 계속 실행 (설정에서 끌 수 있음)
    /// 메뉴바 '종료'·⌘Q는 Apple Event 없이 terminate를 부르므로 그대로 종료된다
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppVisibilityManager.shared.keepsRunningOnDockQuit,
              AppVisibilityManager.shared.showsMenuBarIcon,
              Self.isQuitFromDock() else { return .terminateNow }
        NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }.forEach { $0.close() }
        NSApp.setActivationPolicy(.accessory)
        SwitchHUD.show(title: String(localized: "메뉴바에서 계속 실행 중"),
                       subtitle: String(localized: "완전히 끄려면 메뉴바에서 ‘종료’를 누르세요"),
                       force: true, duration: 2.5)
        return .terminateCancel
    }

    /// 종료 요청이 Dock에서 왔는지: 바깥에서 온 '종료' Apple Event이면서 로그아웃·재시동·시스템 종료 사유가 없을 때
    private static func isQuitFromDock() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication) else { return false }
        return event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) == nil
            && event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)) == nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // 메뉴바 앱에서 Dock 아이콘 클릭 시 메인 창 열기
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        // Dock에서 종료해 숨겼던 Dock 아이콘을 다시 보인다
        AppVisibilityManager.shared.applyCurrentDockPreference()
        return true
    }

    /// 마지막 창을 X로 닫으면 Dock 아이콘을 숨긴다. 메뉴바 '열기'·Dock 재실행 때 다시 보인다
    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing.canBecomeMain,
              AppVisibilityManager.shared.hidesDockOnWindowClose,
              AppVisibilityManager.shared.showsMenuBarIcon else { return }
        let othersOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.canBecomeMain }
        guard !othersOpen else { return }
        // 창이 다 닫힌 뒤에 바꿔야 닫히는 애니메이션이 끊기지 않는다
        DispatchQueue.main.async {
            guard !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func handleDockVisibilityChanged() {
        AppVisibilityManager.shared.applyCurrentDockPreference(activateIfNeeded: true)
    }
}

// MARK: - HotKeyShortcut
// 전역 단축키 (Carbon 키 코드 + 수정키). 화면 표시 글자는 녹화할 때 자판에서 읽은 글자를 그대로 저장한다

struct HotKeyShortcut: Equatable, Codable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var keyLabel: String

    /// ⌥M은 영문 입력(µ)과 다른 앱 단축키를 가로채서 ⌃⌥M으로 바꿨다
    static let `default` = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_M),
        carbonModifiers: UInt32(controlKey | optionKey),
        keyLabel: "M"
    )

    var displayString: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + keyLabel
    }

    /// 녹화한 키 입력 → 단축키. 글자 입력을 가로채지 않도록 ⌃ 또는 ⌘가 있어야 한다
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        guard modifiers & UInt32(controlKey | cmdKey) != 0 else { return nil }

        let code = Int(event.keyCode)
        let label: String
        if let special = Self.specialKeyLabels[code] {
            label = special
        } else if let ascii = Self.asciiLabel(for: event.keyCode) {
            label = ascii
        } else if let characters = event.charactersIgnoringModifiers?.uppercased(),
                  let scalar = characters.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(scalar) {
            label = characters
        } else {
            return nil
        }
        self.init(keyCode: UInt32(code), carbonModifiers: modifiers, keyLabel: label)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.keyLabel = keyLabel
    }

    /// 한글 입력 중에도 ㅅ 대신 T처럼 보이도록, 영문 자판 배열에서 키 글자를 읽는다
    private static func asciiLabel(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: characters, count: length).uppercased()
            guard let scalar = text.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) else { return nil }
            return text
        }
    }

    private static let specialKeyLabels: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]
}

// MARK: - HotKeyManager
// 전환 모드 순환 전역 단축키. 바꾸거나 끌 수 있고, 등록에 실패하면 설정 탭에 알린다

final class HotKeyManager: ObservableObject {
    static let shared = HotKeyManager()

    private static let shortcutKey = "toggle_hotkey"
    private static let enabledKey = "toggle_hotkey_enabled"

    @Published private(set) var shortcut: HotKeyShortcut
    @Published private(set) var isEnabled: Bool
    @Published private(set) var registrationFailed = false

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4D54524B), id: 1)

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.shortcutKey),
           let stored = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            shortcut = stored
        } else {
            shortcut = .default
        }
        isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// 켜져 있을 때 표시할 단축키 글자 (꺼져 있으면 nil)
    var activeDisplayString: String? {
        isEnabled ? shortcut.displayString : nil
    }

    func update(shortcut newShortcut: HotKeyShortcut) {
        shortcut = newShortcut
        if let data = try? JSONEncoder().encode(newShortcut) {
            UserDefaults.standard.set(data, forKey: Self.shortcutKey)
        }
        registerToggleTrackpadHotKey()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        registerToggleTrackpadHotKey()
    }

    func registerToggleTrackpadHotKey() {
        unregisterToggleTrackpadHotKey()
        guard isEnabled else {
            registrationFailed = false
            return
        }

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

        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        registrationFailed = status != noErr
        if registrationFailed {
            print("⚠️ 단축키 등록 실패: \(shortcut.displayString) status=\(status)")
        }
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
    static let showSettingsTab = Notification.Name("showSettingsTab")
}

// MARK: - AppLanguage
// 앱 화면 언어 (한국어 / English). 기본은 시스템 언어와 상관없이 한국어.
// macOS의 앱별 언어 설정(AppleLanguages, 시스템 설정 › 일반 › 언어 및 지역 › 앱)과 같은 값을 쓴다. 바꾸면 다시 시작해야 적용된다

// MARK: - AppTheme
// 화면 모드: 시스템 설정에 맞춤(기본) / 라이트 / 다크. 앱 전체(메인 창·메뉴바 팝오버)에 바로 적용된다

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let key = "app_theme"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .system: return "시스템 설정에 맞춤"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }

    static var selected: AppTheme {
        UserDefaults.standard.string(forKey: key).flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    private static let preferenceKey = "AppleLanguages"

    var id: String { rawValue }

    /// 언어 이름은 그 언어로 보여준다
    var nativeName: String {
        switch self {
        case .korean: return "한국어"
        case .english: return "English"
        }
    }

    /// 이 앱에 저장된 언어 (없으면 한국어)
    static var selected: AppLanguage {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        let first = (domain?[preferenceKey] as? [String])?.first ?? ""
        return first.hasPrefix("en") ? .english : .korean
    }

    /// 지금 화면에 쓰이는 언어
    static var running: AppLanguage {
        Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? .english : .korean
    }

    /// 앱이 문구를 찾기 전에(앱 시작 직후) 부른다. 저장된 언어가 없으면 한국어로 고정한다
    static func applyDefaultIfNeeded() {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
        if domain?[preferenceKey] == nil {
            UserDefaults.standard.set([AppLanguage.korean.rawValue], forKey: preferenceKey)
        }
    }

    static func select(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: preferenceKey)
    }

    /// 앱을 끄고 1초 뒤 다시 연다
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// 개발자 모드: 켜면 트랙패드 탭에 장치·전환 로그 패널을 보여준다 (기본 꺼짐)
enum DeveloperMode {
    static let key = "developer_mode"
}

enum AppInfo {
    /// 화면에 보이는 앱 이름 (Xcode 프로젝트·타깃·번들 ID는 예전 이름 MagicTrack 그대로)
    static let name = "MagicMagicTrack"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionDescription: String {
        String(localized: "버전 \(shortVersion) (\(buildNumber))")
    }

    static var compactVersionDescription: String {
        "v\(shortVersion)"
    }
}

final class AppVisibilityManager {
    static let shared = AppVisibilityManager()
    static let showDockIconKey = "showDockIcon"
    static let showMenuBarIconKey = "showMenuBarIcon"
    static let keepRunningOnDockQuitKey = "keep_running_on_dock_quit"
    static let hideDockOnWindowCloseKey = "hide_dock_on_window_close"

    private init() {}

    var showsDockIcon: Bool {
        if let storedValue = UserDefaults.standard.object(forKey: Self.showDockIconKey) as? Bool {
            return storedValue
        }
        return true
    }

    /// Dock에서 종료해도 메뉴바에서 계속 실행 (기본 켬)
    var keepsRunningOnDockQuit: Bool {
        UserDefaults.standard.object(forKey: Self.keepRunningOnDockQuitKey) as? Bool ?? true
    }

    /// 창을 닫으면 Dock 아이콘을 숨기고 메뉴바에서만 실행 (기본 켬)
    var hidesDockOnWindowClose: Bool {
        UserDefaults.standard.object(forKey: Self.hideDockOnWindowCloseKey) as? Bool ?? true
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
