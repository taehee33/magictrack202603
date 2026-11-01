import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

// MARK: - SettingsView
// 메인 창 '설정' 탭. 별도 설정 창(⌘,)은 없애고 모든 설정을 여기 모았다 (⌘,도 이 탭을 연다)

struct SettingsView: View {
    @EnvironmentObject var trackpadManager: TrackpadManager
    @EnvironmentObject var presetManager: PresetManager
    @EnvironmentObject var appSwitcherManager: AppSwitcherManager

    @AppStorage(AppVisibilityManager.showDockIconKey) private var showDockIcon = true
    @AppStorage(AppVisibilityManager.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(SwitchHUD.enabledKey) private var showSwitchHUD = true
    @AppStorage(AppVisibilityManager.keepRunningOnDockQuitKey) private var keepRunningOnDockQuit = true
    @AppStorage(BatteryMonitor.alertEnabledKey) private var lowBatteryAlert = true
    @AppStorage(BatteryMonitor.thresholdKey) private var lowBatteryThreshold = 20
    @ObservedObject private var battery = BatteryMonitor.shared
    @AppStorage(DeveloperMode.key) private var developerMode = false
    @AppStorage(MenuBarIcon.showsLabelKey) private var menuBarShowsLabel = true
    @ObservedObject private var rotationEngine = RotationEngine.shared
    @ObservedObject private var hotKeys = HotKeyManager.shared
    @ObservedObject private var updateChecker = UpdateChecker.shared
    @ObservedObject private var permissions = PermissionManager.shared
    @State private var showResetPermissionConfirm = false
    @AppStorage(UpdateChecker.autoCheckKey) private var autoCheckUpdates = true
    @AppStorage(AppTheme.key) private var theme = AppTheme.system.rawValue

    @State private var loginItemStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?
    @State private var showResetPresetsConfirm = false
    @State private var showAddAppRuleSheet = false
    @State private var language = AppLanguage.selected

    var body: some View {
        Form {
            Section("시작") {
                Toggle("로그인 시 자동 시작", isOn: Binding(
                    get: { loginItemStatus == .enabled || loginItemStatus == .requiresApproval },
                    set: { setLaunchAtLogin($0) }
                ))

                if loginItemStatus == .requiresApproval {
                    HStack {
                        Text("시스템 설정 › 로그인 항목에서 \(AppInfo.name)을 허용해야 자동 시작돼요.")
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

                Toggle("메뉴바에 사용 중인 트랙패드와 회전 표시", isOn: $menuBarShowsLabel)
                    .disabled(!showMenuBarIcon)

                Toggle("Dock에서 종료해도 메뉴바에서 계속 실행", isOn: $keepRunningOnDockQuit)
                    .disabled(!showMenuBarIcon)
                    .help(String(localized: "Dock 아이콘의 ‘종료’는 Dock 아이콘만 숨겨요. 완전히 끄려면 메뉴바에서 ‘종료’를 누르세요."))

                Text(visibilityDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("화면 모드") {
                Picker("화면 모드", selection: $theme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .onChange(of: theme) { _, newValue in
                    (AppTheme(rawValue: newValue) ?? .system).apply()
                }
            }

            Section("언어") {
                Picker("언어", selection: Binding(
                    get: { language },
                    set: { newValue in
                        language = newValue
                        AppLanguage.select(newValue)
                    }
                )) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.nativeName).tag(option)
                    }
                }

                if language != AppLanguage.running {
                    HStack {
                        Text("다시 시작하면 바뀐 언어로 보여요.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("지금 다시 시작") {
                            AppLanguage.relaunch()
                        }
                        .controlSize(.small)
                    }
                }
            }

            batterySection

            Section("트랙패드 전환") {
                Toggle("전환할 때 화면에 알림 보이기", isOn: $showSwitchHUD)

                Toggle("전환 모드 단축키 사용", isOn: Binding(
                    get: { hotKeys.isEnabled },
                    set: { hotKeys.setEnabled($0) }
                ))

                if hotKeys.isEnabled {
                    LabeledContent("단축키 (자동 → 내장 고정 → 매직 고정)") {
                        HStack(spacing: 8) {
                            ShortcutRecorder()
                            Button("기본값") {
                                hotKeys.update(shortcut: .default)
                            }
                            .disabled(hotKeys.shortcut == .default)
                        }
                    }

                    if hotKeys.registrationFailed {
                        Text("\(hotKeys.shortcut.displayString) 단축키를 등록하지 못했어요. 다른 앱이 쓰고 있을 수 있어요. 다른 조합을 지정해 주세요.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }

                    Text("버튼을 누른 뒤 원하는 조합을 누르세요. 글자 입력을 가로채지 않도록 ⌃ 또는 ⌘가 들어간 조합만 쓸 수 있어요. 취소는 esc.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
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
                    let lostRules = presetManager.rulesLostOnReset()
                    Text(lostRules > 0
                         ? String(localized: "직접 만들거나 고친 프리셋이 모두 지워지고 기본 프리셋 4개로 돌아가요. 되돌릴 수 없어요. 직접 만든 프리셋을 쓰는 앱 규칙 \(lostRules)개는 ‘프리셋 없음’이 돼요.")
                         : String(localized: "직접 만들거나 고친 프리셋이 모두 지워지고 기본 프리셋 4개로 돌아가요. 되돌릴 수 없어요."))
                }
            }

            Section("고급") {
                Toggle("개발자 모드", isOn: $developerMode)
                Text("트랙패드 탭 아래에 장치 연결·터치 감지·전환 기록을 보여줘요. 문제를 알릴 때 도움이 돼요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section("정보") {
                LabeledContent("버전", value: "\(AppInfo.shortVersion) (\(AppInfo.buildNumber))")
                Text("맥북 내장 트랙패드와 블루투스 매직 트랙패드의 감도를 개별적으로 조절합니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            updateSection
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

    // MARK: - 업데이트

    private var updateSection: some View {
        Section("업데이트") {
            Toggle("새 버전 자동 확인 (하루 한 번)", isOn: $autoCheckUpdates)
                .onChange(of: autoCheckUpdates) { _, isOn in
                    if isOn { updateChecker.start() }
                }

            HStack {
                updateStatusText
                Spacer()
                if let release = updateChecker.availableRelease {
                    Button("다운로드 페이지 열기") {
                        NSWorkspace.shared.open(release.page)
                    }
                } else {
                    Button("지금 확인") {
                        updateChecker.check()
                    }
                    .disabled(updateChecker.status == .checking)
                }
            }

            Text("GitHub 릴리스 페이지만 확인해요. 새 버전은 직접 받아서 응용 프로그램 폴더의 앱을 바꿔 주세요.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var updateStatusText: some View {
        switch updateChecker.status {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("확인하는 중…")
            }
        case .available(let release):
            Label("새 버전(\(release.version))이 있어요", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
        case .upToDate:
            Text("최신 버전이에요")
        case .failed:
            Text("확인하지 못했어요. 인터넷 연결을 확인해 주세요.")
                .foregroundStyle(.secondary)
        case .idle:
            if let last = updateChecker.lastChecked {
                Text("마지막 확인: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            } else {
                Text("아직 확인하지 않았어요")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 앱 자동전환

    private var batterySection: some View {
        Section("매직 트랙패드 배터리") {
            LabeledContent("남은 배터리") {
                if battery.percent != nil {
                    BatteryBadge()
                } else {
                    Text(trackpadManager.magicTrackpad == nil ? LocalizedStringKey("연결 없음") : "확인할 수 없음")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("배터리가 부족하면 알림 보내기", isOn: $lowBatteryAlert)
                .onChange(of: lowBatteryAlert) { _, enabled in
                    if enabled { battery.evaluateAlert() }
                }

            if lowBatteryAlert {
                Picker("알림 기준", selection: $lowBatteryThreshold) {
                    ForEach(BatteryMonitor.thresholdOptions, id: \.self) { value in
                        Text(verbatim: "\(value)%").tag(value)
                    }
                }
                .onChange(of: lowBatteryThreshold) { _, _ in battery.evaluateAlert() }

                if battery.notificationsDenied {
                    HStack {
                        Text("알림이 꺼져 있어요. 시스템 설정 › 알림에서 MagicMagicTrack 알림을 허용해 주세요.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("알림 설정 열기") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                        .controlSize(.small)
                    }
                }

                Text("기준 아래로 떨어질 때 한 번, 5% 이하일 때 한 번 더 알려요. 충전하면 다시 알릴 준비를 해요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            battery.refresh()
            battery.refreshNotificationStatus()
        }
    }

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
                    AppRuleRow(rule: rule) { presetID in
                        appSwitcherManager.setPreset(presetID, forRule: rule.id)
                    } onDelete: {
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

            LabeledContent("손쉬운 사용") {
                if permissions.hasAccessibility {
                    Label("허용됨", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("허용 안 됨", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                if !permissions.hasAccessibility {
                    Button("허용하기") {
                        permissions.requestAccessibility()
                        permissions.openPrivacySettings()
                    }
                }
                Button("권한 다시 등록…") { showResetPermissionConfirm = true }
                Spacer()
                Button("앱 위치 보기") { permissions.revealAppInFinder() }
            }
            .confirmationDialog("손쉬운 사용 권한을 다시 등록할까요?", isPresented: $showResetPermissionConfirm) {
                Button("다시 등록") { permissions.resetAccessibility() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("목록에서 이 앱 항목을 지우고 다시 추가해요. 이어서 뜨는 창이나 시스템 설정에서 \(AppInfo.name)을 다시 켜 주세요.")
            }

            Text("목록에서 켜져 있는데도 90° 회전이 안 되면 '권한 다시 등록'을 눌러 주세요. 앱을 업데이트하거나 다시 빌드하면 macOS가 새 앱으로 보고 예전 허용을 쓰지 않을 수 있어요.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            if permissions.lastResetFailed {
                Text("목록에서 지우지 못했어요. 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 \(AppInfo.name)을 −로 지운 뒤 +로 다시 추가해 주세요.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            Text("이 앱 위치: \(permissions.appPath)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            permissions.checkAccessibility()
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
                ? String(localized: "자동 시작을 켜지 못했어요: \(error.localizedDescription)")
                : String(localized: "자동 시작을 끄지 못했어요: \(error.localizedDescription)")
        }
        refreshLoginItemStatus()
    }

    private func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    private var visibilityDescription: String {
        switch (showDockIcon, showMenuBarIcon) {
        case (true, true):
            return String(localized: "실행 중일 때 Dock과 메뉴바에 함께 표시됩니다.")
        case (true, false):
            return String(localized: "Dock에만 표시됩니다.")
        case (false, true):
            return String(localized: "메뉴바에만 표시됩니다.")
        case (false, false):
            return String(localized: "앱 접근성을 위해 Dock 또는 메뉴바 중 하나는 항상 유지됩니다.")
        }
    }
}

// MARK: - ShortcutRecorder
// 누르면 다음 키 입력을 단축키로 받는다. 받는 동안에는 기존 전역 단축키를 잠시 풀어 같은 조합도 다시 지정할 수 있게 한다

private struct ShortcutRecorder: View {
    @ObservedObject private var hotKeys = HotKeyManager.shared
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var showsRejected = false

    var body: some View {
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: 110)
        }
        .tint(isRecording ? .accentColor : nil)
        .buttonStyle(.bordered)
        .onDisappear(perform: stopRecording)
    }

    private var label: String {
        if !isRecording { return hotKeys.shortcut.displayString }
        return showsRejected ? String(localized: "⌃ 또는 ⌘와 함께") : String(localized: "키를 누르세요…")
    }

    private func startRecording() {
        isRecording = true
        showsRejected = false
        hotKeys.unregisterToggleTrackpadHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
            } else if let shortcut = HotKeyShortcut(event: event) {
                hotKeys.update(shortcut: shortcut)
                stopRecording()
            } else {
                showsRejected = true
            }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        hotKeys.registerToggleTrackpadHotKey()
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
