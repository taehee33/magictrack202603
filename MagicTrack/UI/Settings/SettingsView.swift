import SwiftUI
import ServiceManagement

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var trackpadManager: TrackpadManager
    @EnvironmentObject var presetManager: PresetManager
    @EnvironmentObject var appSwitcherManager: AppSwitcherManager
    @StateObject private var permissionManager = PermissionManager.shared

    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage(AppVisibilityManager.showDockIconKey) private var showDockIcon = true
    @AppStorage(AppVisibilityManager.showMenuBarIconKey) private var showMenuBarIcon = true

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("일반", systemImage: "gear")
                }

            permissionsSettings
                .tabItem {
                    Label("권한", systemImage: "lock.shield")
                }

            aboutView
                .tabItem {
                    Label("정보", systemImage: "info.circle")
                }
        }
        .frame(width: 480, height: 300)
    }

    // MARK: - 일반 설정

    private var generalSettings: some View {
        Form {
            Section("시작") {
                Toggle("로그인 시 자동 시작", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newVal in
                        if #available(macOS 13.0, *) {
                            if newVal {
                                try? SMAppService.mainApp.register()
                            } else {
                                try? SMAppService.mainApp.unregister()
                            }
                        }
                    }

                Toggle("앱 실행 중 Dock에 보이기", isOn: $showDockIcon)
                    .onChange(of: showDockIcon) { _, _ in
                        AppVisibilityManager.shared.ensureAtLeastOneVisible(changedKey: AppVisibilityManager.showDockIconKey)
                        NotificationCenter.default.post(name: .dockVisibilityChanged, object: nil)
                    }

                Toggle("앱 실행 중 메뉴바에 보이기", isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { _, _ in
                        AppVisibilityManager.shared.ensureAtLeastOneVisible(changedKey: AppVisibilityManager.showMenuBarIconKey)
                    }

                Text(visibilityDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("앱 자동전환") {
                Toggle("앱 변경 시 프리셋 자동 적용", isOn: Binding(
                    get: { appSwitcherManager.isEnabled },
                    set: { _ in appSwitcherManager.toggleEnabled() }
                ))
            }

            Section("데이터") {
                Button("모든 프리셋 초기화") {
                    presetManager.resetToDefaultPresetsAndSave()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - 권한 설정

    private var permissionsSettings: some View {
        VStack(spacing: 16) {
            PermissionRow(
                icon: "keyboard",
                title: "입력 모니터링",
                description: "트랙패드 감도를 변경하려면 필요합니다",
                isGranted: permissionManager.hasInputMonitoring
            ) {
                permissionManager.openPrivacySettings(section: "Privacy_InputMonitoring")
            }

            PermissionRow(
                icon: "accessibility",
                title: "손쉬운 사용",
                description: "앱 자동전환 기능에 필요합니다 (선택 사항)",
                isGranted: permissionManager.hasAccessibility
            ) {
                permissionManager.requestAccessibility()
            }

            Button("권한 상태 새로고침") {
                permissionManager.checkPermissions()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - 정보

    private var aboutView: some View {
        VStack(spacing: 12) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                )

            Text("MagicTrack")
                .font(.system(size: 20, weight: .bold))

            Text(AppInfo.versionDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("맥북 내장 트랙패드와 블루투스 매직 트랙패드의\n감도를 개별적으로 조절합니다.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Dock 표시: \(showDockIcon ? "켜짐" : "꺼짐")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text("메뉴바 표시: \(showMenuBarIcon ? "켜짐" : "꺼짐")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var visibilityDescription: String {
        switch (showDockIcon, showMenuBarIcon) {
        case (true, true):
            return "실행 중일 때 Dock과 메뉴바에 함께 표시됩니다."
        case (true, false):
            return "Dock에만 표시됩니다."
        case (false, true):
            return "메뉴바에만 표시됩니다."
        case (false, false):
            return "앱 접근성을 위해 Dock 또는 메뉴바 중 하나는 항상 유지됩니다."
        }
    }
}

// MARK: - PermissionRow

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("허용") { onAction() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.primary.opacity(0.04))
        )
    }
}
