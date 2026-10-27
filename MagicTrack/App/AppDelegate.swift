import AppKit
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
