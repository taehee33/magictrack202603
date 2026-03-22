import Foundation
import AppKit
import ApplicationServices

// MARK: - PermissionManager

final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasInputMonitoring: Bool = false
    @Published var hasAccessibility: Bool = false
    @Published var showPermissionAlert: Bool = false

    private init() {}

    func checkPermissions() {
        checkInputMonitoring()
        checkAccessibility()
    }

    func checkInputMonitoring() {
        // Input Monitoring은 접근성 API가 아닌 CGEvent Listen 권한으로 확인
        hasInputMonitoring = CGPreflightListenEventAccess()
    }

    func checkAccessibility() {
        hasAccessibility = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openPrivacySettings(section: String = "Privacy_InputMonitoring") {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)")!
        NSWorkspace.shared.open(url)
    }
}
