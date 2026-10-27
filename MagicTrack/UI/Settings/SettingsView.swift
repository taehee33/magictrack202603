import SwiftUI
import ServiceManagement

// MARK: - SettingsView
// 메인 창 '설정' 탭. 별도 설정 창(⌘,)은 없애고 모든 설정을 여기 모았다 (⌘,도 이 탭을 연다)

struct SettingsView: View {
    @EnvironmentObject var trackpadManager: TrackpadManager
    @EnvironmentObject var presetManager: PresetManager
    @EnvironmentObject var appSwitcherManager: AppSwitcherManager

    @AppStorage(AppVisibilityManager.showDockIconKey) private var showDockIcon = true
    @AppStorage(AppVisibilityManager.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(SwitchHUD.enabledKey) private var showSwitchHUD = true
    @ObservedObject private var rotationEngine = RotationEngine.shared

    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?
    @State private var showResetPresetsConfirm = false
    @State private var showAddAppRuleSheet = false

    var body: some View {
        Form {
            Section("시작") {
                Toggle("로그인 시 자동 시작", isOn: Binding(
                    get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }
                ))

                if loginItemStatus == .requiresApproval {
                    HStack {
                        Text("시스템 설정 › 로그인 항목에서 MagicTrack을 허용해야 자동 시작돼요.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("시스템 설정 열기") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .controlSize(.small)
                    }
                }

                if let loginItemError {
                    Text(loginItemError)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
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

            Section("트랙패드 전환") {
                Toggle("전환할 때 화면에 알림 보이기", isOn: $showSwitchHUD)
            }

            appRulesSection

            permissionsSection

            Section("데이터") {
                Button("모든 프리셋 초기화…") {
                    showResetPresetsConfirm = true
                }
                .foregroundStyle(.red)
                .confirmationDialog("모든 프리셋을 초기화할까요?", isPresented: $showResetPresetsConfirm) {
                    Button("초기화", role: .destructive) {
                        presetManager.resetToDefaultPresetsAndSave()
                    }
                    Button("취소", role: .cancel) {}
                } message: {
                    Text("직접 만들거나 고친 프리셋이 모두 지워지고 기본 프리셋 4개로 돌아가요. 되돌릴 수 없어요.")
                }
            }

            Section("정보") {
                LabeledContent("버전", value: "\(AppInfo.shortVersion) (\(AppInfo.buildNumber))")
                Text("맥북 내장 트랙패드와 블루투스 매직 트랙패드의 감도를 개별적으로 조절합니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshLoginItemStatus)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 시스템 설정 › 로그인 항목에서 바꾸고 돌아온 경우
            refreshLoginItemStatus()
        }
        .sheet(isPresented: $showAddAppRuleSheet) {
            AddAppRuleSheet(
                presetManager: presetManager,
                appSwitcherManager: appSwitcherManager,
                onDismiss: { showAddAppRuleSheet = false }
            )
        }
    }

    // MARK: - 앱 자동전환

    private var appRulesSection: some View {
        Section {
            Toggle("앱 변경 시 프리셋 자동 적용", isOn: Binding(
                get: { appSwitcherManager.isEnabled },
                set: { _ in appSwitcherManager.toggleEnabled() }
            ))

            if appSwitcherManager.rules.isEmpty {
                Text("앱 규칙이 없어요. 특정 앱을 쓸 때 적용할 프리셋을 정해 보세요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appSwitcherManager.rules) { rule in
                    AppRuleRow(rule: rule) {
                        appSwitcherManager.deleteRule(id: rule.id)
                    }
                }
            }
        } header: {
            HStack {
                Text("앱 자동전환")
                Spacer()
                Button {
                    showAddAppRuleSheet = true
                } label: {
                    Label("규칙 추가", systemImage: "plus.circle")
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - 권한

    private var permissionsSection: some View {
        Section("권한") {
            Label("기본 기능은 추가 권한 없이 동작해요", systemImage: "checkmark.shield")
            Text("감도·스크롤·클릭 압력 적용, 만진 트랙패드로 자동 전환, 앱 자동전환에는 권한이 필요하지 않아요. 매직 트랙패드를 **90°로 회전**할 때만 손쉬운 사용 권한이 필요해요. (180°는 권한 없이 동작)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if rotationEngine.needsAccessibility {
                Button("손쉬운 사용 권한 열기") { rotationEngine.requestAccessibility() }
            }
        }
    }

    // MARK: - 로그인 시 자동 시작
    // 저장값 대신 SMAppService 상태를 그대로 보여준다 (시스템 설정에서 꺼도 맞게 보이도록)

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = enabled
                ? "자동 시작을 켜지 못했어요: \(error.localizedDescription)"
                : "자동 시작을 끄지 못했어요: \(error.localizedDescription)"
        }
        refreshLoginItemStatus()
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
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
