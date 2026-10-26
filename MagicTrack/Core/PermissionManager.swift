import Foundation
import AppKit
import ApplicationServices

// MARK: - PermissionManager

final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var hasAccessibility: Bool = false
    @Published var showPermissionAlert: Bool = false

    private init() {}

    func checkPermissions() {
        checkAccessibility()
    }

    func checkAccessibility() {
        hasAccessibility = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openPrivacySettings(section: String = "Privacy_Accessibility") {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)")!
        NSWorkspace.shared.open(url)
    }
}
