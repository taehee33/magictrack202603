import Foundation
import AppKit
import ApplicationServices
import CoreServices

// MARK: - PermissionManager

final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasAccessibility: Bool = false
    @Published var showPermissionAlert: Bool = false
    @Published private(set) var lastResetFailed = false

    /// 지금 실행 중인 앱의 위치 (시스템 설정 목록에 직접 추가할 때 이 앱을 골라야 한다)
    var appPath: String { Bundle.main.bundlePath }

    private init() {}

    func checkPermissions() {
        checkAccessibility()
    }

    func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        if hasAccessibility != trusted { hasAccessibility = trusted }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openPrivacySettings(section: String = "Privacy_Accessibility") {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)")!
        NSWorkspace.shared.open(url)
    }

    /// 손쉬운 사용 목록에서 이 앱 항목을 지우고 다시 추가한다.
    /// 앱을 새로 빌드·업데이트해 서명이 바뀌면 목록에는 켜져 있어도 예전 앱 기준이라 동작하지 않는다.
    /// 같은 번들 ID의 다른 사본이 시스템에 등록돼 있으면 설정이 엉뚱한 사본을 가리키므로 지금 앱을 다시 등록한다
    func resetAccessibility() {
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "com.magictrack.app"]
        do {
            try process.run()
            process.waitUntilExit()
            lastResetFailed = process.terminationStatus != 0
        } catch {
            lastResetFailed = true
        }

        checkAccessibility()
        RotationEngine.shared.recheckPermission()
        requestAccessibility()
        openPrivacySettings()
    }

    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}
