import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - MainView

struct MainView: View {
    @EnvironmentObject var trackpadManager: TrackpadManager
    @EnvironmentObject var presetManager: PresetManager
    @EnvironmentObject var appSwitcherManager: AppSwitcherManager
    @AppStorage(AppVisibilityManager.showDockIconKey) private var showDockIcon = true
    @AppStorage(AppVisibilityManager.showMenuBarIconKey) private var showMenuBarIcon = true

    @State private var showSavePresetSheet = false
    @State private var showAddAppRuleSheet = false
    @State private var showBluetoothPickerSheet = false
    @State private var newPresetName = ""
    @State private var newPresetEmoji = "⚡"
    @State private var selectedTab: Tab = .devices
    @State private var selectedDeviceType: TrackpadType = .internal

    enum Tab: String, CaseIterable {
        case devices = "트랙패드"
        case presets = "프리셋"
        case appRules = "설정"
        
        var icon: String {
            switch self {
            case .devices: return "rectangle.roundedtop.fill"
            case .presets: return "slider.horizontal.3"
            case .appRules: return "gearshape"
            }
        }
    }

    // 트랙패드가 연결되지 않은 경우 더미 모델 사용 (UI 테스트용)
    var internalDevice: TrackpadDevice {
        trackpadManager.internalTrackpad ?? TrackpadDevice(
            hidDevice: nil, type: .internal, productName: "내장 트랙패드"
        )
    }

    var magicDevice: TrackpadDevice? {
        trackpadManager.magicTrackpad
    }

    var body: some View {
        VStack(spacing: 0) {
            // ─ 헤더 ─
            headerView

            Divider()

            // ─ 탭 내비게이션 ─
            tabBar

            // ─ 콘텐츠 ─
            Group {
                switch selectedTab {
                case .devices:
                    devicesTab
                case .presets:
                    presetsTab
                case .appRules:
                    appRulesTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .windowBackgroundColor).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .sheet(isPresented: $showSavePresetSheet) {
            savePresetSheet
        }
        .sheet(isPresented: $showAddAppRuleSheet) {
            AddAppRuleSheet(
                presetManager: presetManager,
                appSwitcherManager: appSwitcherManager,
                onDismiss: { showAddAppRuleSheet = false }
            )
        }
        .sheet(isPresented: $showBluetoothPickerSheet) {
            BluetoothDevicePickerSheet(
                trackpadManager: trackpadManager,
                onDismiss: { showBluetoothPickerSheet = false }
            )
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // 앱 아이콘
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                Image(systemName: "rectangle.roundedtop.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("MagicTrack")
                        .font(.system(size: 18, weight: .bold))
                    Text(AppInfo.compactVersionDescription)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                Text("트랙패드 개별 감도 조절")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // 상태 뱃지
            HStack(spacing: 6) {
                let connectedCount = [
                    trackpadManager.internalTrackpad != nil ? 1 : 0,
                    trackpadManager.magicTrackpad != nil ? 1 : 0
                ].reduce(0, +)

                Circle()
                    .fill(connectedCount > 0 ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text("\(connectedCount)개 연결됨")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(.primary.opacity(0.06)))

            if connectedActiveLabel != nil || connectedLastSwitchText != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let connectedActiveLabel {
                        Text("현재 적용: \(connectedActiveLabel)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    if let connectedLastSwitchText {
                        Text("마지막 전환: \(connectedLastSwitchText)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? .white : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selectedTab == tab ? Color.blue : .clear)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(.primary.opacity(0.05))
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Devices Tab

    private var devicesTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                devicePicker
                capabilityNoticeCard

                TrackpadCardView(
                    device: internalDevice,
                    accentColor: .blue,
                    currentPresetLabel: presetManager.activePreset.map { "\($0.emoji) \($0.name)" },
                    isCurrentlyActive: trackpadManager.activeTrackpadType == .internal,
                    lastSwitchedAt: trackpadManager.activeTrackpadType == .internal ? trackpadManager.lastActiveSwitchAt : nil
                ) {
                    guard trackpadManager.internalTrackpad != nil else { return }
                    trackpadManager.applySettings(for: internalDevice)
                } onActivate: {
                    selectedDeviceType = .internal
                    trackpadManager.activateProfileManually(for: .internal)
                }

                if let magic = magicDevice {
                    VStack(spacing: 8) {
                        TrackpadCardView(
                            device: magic,
                            accentColor: .purple,
                            currentPresetLabel: presetManager.activePreset.map { "\($0.emoji) \($0.name)" },
                            isCurrentlyActive: trackpadManager.activeTrackpadType == .magicTrackpad,
                            lastSwitchedAt: trackpadManager.activeTrackpadType == .magicTrackpad ? trackpadManager.lastActiveSwitchAt : nil
                        ) {
                            trackpadManager.applySettings(for: magic)
                        } onActivate: {
                            selectedDeviceType = .magicTrackpad
                            trackpadManager.activateProfileManually(for: .magicTrackpad)
                        }
                        Button {
                            showBluetoothPickerSheet = true
                        } label: {
                            Label("다른 기기로 변경", systemImage: "rectangle.roundedtop.badge.plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.purple)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    MagicTrackpadPlaceholder(onSelectDevice: { showBluetoothPickerSheet = true })
                }

                // 현재 설정 저장 버튼
                Button {
                    showSavePresetSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("현재 설정을 프리셋으로 저장")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                inputDebugPanel
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            syncSelectedDeviceType()
        }
        .onChange(of: trackpadManager.magicTrackpad != nil) { _, _ in
            syncSelectedDeviceType()
        }
    }

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("빠른 전환 (option + M)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                shortcutHint

                Spacer()
            }

            HStack(spacing: 8) {
                devicePickerButton(
                    type: .internal,
                    title: "내장 트랙패드",
                    subtitle: deviceStatusText(for: .internal),
                    icon: "laptopcomputer",
                    color: .blue,
                    isAvailable: trackpadManager.internalTrackpad != nil
                )

                devicePickerButton(
                    type: .magicTrackpad,
                    title: "매직 트랙패드",
                    subtitle: deviceStatusText(for: .magicTrackpad),
                    icon: "rectangle.roundedtop.fill",
                    color: .purple,
                    isAvailable: trackpadManager.magicTrackpad != nil
                )
            }
        }
    }

    private var shortcutHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.system(size: 10, weight: .semibold))
            Text("⌥M")
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func devicePickerButton(
        type: TrackpadType,
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isAvailable: Bool
    ) -> some View {
        Button {
            guard isAvailable else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDeviceType = type
            }
            trackpadManager.activateProfileManually(for: type)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(selectedDeviceType == type ? 0.18 : 0.1))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isAvailable ? color : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isAvailable ? (selectedDeviceType == type ? color : .secondary) : Color(nsColor: .tertiaryLabelColor))
                }

                Spacer()

                if selectedDeviceType == type {
                    Text("선택")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedDeviceType == type ? color.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    private func deviceStatusText(for type: TrackpadType) -> String {
        let connected: Bool
        switch type {
        case .internal:
            connected = trackpadManager.internalTrackpad != nil
        case .magicTrackpad:
            connected = trackpadManager.magicTrackpad != nil
        }

        guard connected else { return "연결 없음" }
        return trackpadManager.activeTrackpadType == type ? "연결됨 · 적용" : "연결됨 · 적용 대기"
    }

    private func syncSelectedDeviceType() {
        if let activeType = trackpadManager.activeTrackpadType {
            selectedDeviceType = activeType
            return
        }
        if selectedDeviceType == .magicTrackpad, trackpadManager.magicTrackpad == nil {
            selectedDeviceType = .internal
        }
        if selectedDeviceType == .internal, trackpadManager.internalTrackpad == nil, trackpadManager.magicTrackpad != nil {
            selectedDeviceType = .magicTrackpad
        }
    }

    private var connectedActiveLabel: String? {
        trackpadManager.activeTrackpadType?.displayName
    }

    private var connectedLastSwitchText: String? {
        trackpadManager.lastActiveSwitchAt?.formatted(date: .omitted, time: .standard)
    }

    private var inputDebugPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("HID 연결/감시 로그")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("실입력 감지 가능 범위 확인")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    debugCountPill(title: "CONNECT", count: trackpadManager.hidConnectCount, color: .blue)
                    debugCountPill(title: "MONITOR", count: trackpadManager.hidMonitorCount, color: .blue)
                    debugCountPill(title: "ACTIVATE", count: trackpadManager.hidActivateCount, color: .blue)
                }
                HStack(spacing: 6) {
                    debugCountPill(title: "VALUE", count: trackpadManager.hidValueCount, color: .orange)
                    debugCountPill(title: "REPORT", count: trackpadManager.hidReportCount, color: .orange)
                    Spacer()
                }
            }

            Text("현재 구조에서는 CONNECT/MONITOR/수동 ACTIVATE는 확인되지만, VALUE/REPORT는 실제 터치 중에도 0건일 수 있습니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if trackpadManager.recentInputLogs.isEmpty {
                Text("아직 HID 로그가 없습니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(trackpadManager.recentInputLogs) { log in
                        HStack(alignment: .top, spacing: 8) {
                            Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 78, alignment: .leading)

                            Text(log.source.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.blue)
                                .frame(width: 64, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(log.trackpadType?.displayName ?? "미분류") · \(log.deviceName)")
                                    .font(.system(size: 11, weight: .medium))
                                if !log.detail.isEmpty {
                                    Text(log.detail)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func debugCountPill(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(count > 0 ? color : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var capabilityNoticeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("기능 상태 안내")
                    .font(.system(size: 12, weight: .semibold))
                Text("실험/미지원 포함")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
            }

            Text("이동/스크롤/클릭 압력 저장과 수동 적용은 지원됩니다. 회전, 실입력 감지, 좌표/제스처 감지, 입력 기반 자동화는 현재 실험/미지원 상태이며 안내와 저장 위주로만 제공됩니다.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.18), lineWidth: 1)
                )
        )
    }

    // MARK: - Presets Tab

    private var presetsTab: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(presetManager.presets) { preset in
                    PresetCardView(
                        preset: preset,
                        isActive: presetManager.activePresetID == preset.id
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            presetManager.activatePreset(preset)
                        }
                    } onDelete: {
                        presetManager.deletePreset(id: preset.id)
                    }
                }

                // 새 프리셋 추가 버튼
                Button {
                    showSavePresetSheet = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.blue)
                        Text("새 프리셋")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                            .fill(.blue.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Settings Tab

    private var appRulesTab: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsToggleRow(
                    title: "앱 자동전환",
                    description: "앱 실행 시 지정된 프리셋 자동 적용"
                ) {
                    Toggle("", isOn: Binding(
                        get: { appSwitcherManager.isEnabled },
                        set: { _ in appSwitcherManager.toggleEnabled() }
                    ))
                    .labelsHidden()
                }

                Divider()

                settingsToggleRow(
                    title: "앱 실행 중 Dock에 보이기",
                    description: showDockIcon
                        ? "Dock에 앱 아이콘을 표시합니다."
                        : "Dock에는 표시하지 않습니다."
                ) {
                    Toggle("", isOn: $showDockIcon)
                        .labelsHidden()
                        .onChange(of: showDockIcon) { _, _ in
                            AppVisibilityManager.shared.ensureAtLeastOneVisible(changedKey: AppVisibilityManager.showDockIconKey)
                            NotificationCenter.default.post(name: .dockVisibilityChanged, object: nil)
                        }
                }

                Divider()

                settingsToggleRow(
                    title: "앱 실행 중 메뉴바에 보이기",
                    description: showMenuBarIcon
                        ? "메뉴바에서 빠르게 열고 조작할 수 있습니다."
                        : "메뉴바에는 표시하지 않습니다."
                ) {
                    Toggle("", isOn: $showMenuBarIcon)
                        .labelsHidden()
                        .onChange(of: showMenuBarIcon) { _, _ in
                            AppVisibilityManager.shared.ensureAtLeastOneVisible(changedKey: AppVisibilityManager.showMenuBarIconKey)
                        }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("앱 자동전환 규칙")
                                .font(.system(size: 13, weight: .semibold))
                            Text("특정 앱 사용 시 자동으로 감도 프리셋을 전환합니다")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            showAddAppRuleSheet = true
                        } label: {
                            Label("규칙 추가", systemImage: "plus.circle")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                    }

                    if appSwitcherManager.rules.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "app.badge.plus")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                            Text("앱 규칙이 없습니다")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.primary.opacity(0.03))
                        )
                    } else {
                        VStack(spacing: 8) {
                            ForEach(appSwitcherManager.rules) { rule in
                                AppRuleRow(rule: rule) {
                                    appSwitcherManager.deleteRule(id: rule.id)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private func settingsToggleRow<Accessory: View>(
        title: String,
        description: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.03))
    }

    // MARK: - Save Preset Sheet

    private var savePresetSheet: some View {
        VStack(spacing: 20) {
            Text("프리셋 저장")
                .font(.system(size: 16, weight: .bold))

            HStack(spacing: 12) {
                TextField("이모지", text: $newPresetEmoji)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)

                TextField("프리셋 이름", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("취소") {
                    showSavePresetSheet = false
                }
                .buttonStyle(.bordered)

                Button("저장") {
                    if !newPresetName.isEmpty {
                        presetManager.saveCurrentAsPreset(name: newPresetName, emoji: newPresetEmoji)
                        showSavePresetSheet = false
                        newPresetName = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPresetName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

// MARK: - MagicTrackpad Placeholder

struct MagicTrackpadPlaceholder: View {
    var onSelectDevice: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.purple.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: "rectangle.roundedtop.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.purple.opacity(0.5))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("매직 트랙패드")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("블루투스로 연결하거나 기기를 선택하세요")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if onSelectDevice != nil {
                    Button("기기 선택") {
                        onSelectDevice?()
                    }
                    .buttonStyle(.bordered)
                    .tint(.purple)
                } else {
                    Image(systemName: "bluetooth")
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(Color.purple.opacity(0.2))
        )
    }
}

// MARK: - Bluetooth Device Picker Sheet

struct BluetoothDevicePickerSheet: View {
    @ObservedObject var trackpadManager: TrackpadManager
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("매직 트랙패드 선택")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                if !trackpadManager.availableBluetoothDevices.isEmpty && trackpadManager.preferredBluetoothDeviceKey != nil {
                    Button("선택 해제") {
                        trackpadManager.setPreferredBluetoothDevice(key: nil)
                    }
                    .buttonStyle(.bordered)
                }
                Button("닫기") { onDismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if trackpadManager.availableBluetoothDevices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bluetooth")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("감지된 블루투스 기기가 없습니다")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("매직 트랙패드 또는 마우스를 블루투스로 연결한 뒤\n앱을 다시 열어주세요.")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(trackpadManager.availableBluetoothDevices.sorted { d1, d2 in
                            if d1.kind != d2.kind { return d1.kind == .trackpad }
                            return d1.name.localizedCaseInsensitiveCompare(d2.name) == .orderedAscending
                        }) { device in
                            HStack(spacing: 12) {
                                Image(systemName: device.kind == .trackpad ? "rectangle.roundedtop.fill" : "computermouse.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(device.kind == .trackpad ? .purple : .orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(device.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(device.kind.rawValue)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(device.kind == .trackpad ? .purple : .orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill((device.kind == .trackpad ? Color.purple : Color.orange).opacity(0.15)))
                                    }
                                    Text("VID \(String(device.vendorID, radix: 16)) · PID \(String(device.productID, radix: 16))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(trackpadManager.preferredBluetoothDeviceKey == device.id ? "선택됨" : "선택") {
                                    if trackpadManager.preferredBluetoothDeviceKey != device.id {
                                        trackpadManager.setPreferredBluetoothDevice(key: device.id)
                                        onDismiss()
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(trackpadManager.preferredBluetoothDeviceKey == device.id ? .gray : (device.kind == .trackpad ? .purple : .orange))
                                .disabled(trackpadManager.preferredBluetoothDeviceKey == device.id)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }
                    .padding(20)
                }
                Text("트랙패드를 선택하면 감도 설정이 적용됩니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 380, height: 320)
    }
}

// MARK: - PresetCardView

struct PresetCardView: View {
    let preset: TrackpadPreset
    let isActive: Bool
    let onActivate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onActivate) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(preset.emoji)
                        .font(.system(size: 22))
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 14))
                    }
                }

                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 4) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 9))
                    Text(String(format: "%.1f", preset.internalTrackingSpeed))
                        .font(.system(size: 10, design: .monospaced))
                    Text("•")
                    Image(systemName: "rectangle.roundedtop.fill")
                        .font(.system(size: 9))
                    Text(String(format: "%.1f", preset.magicTrackingSpeed))
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.blue.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isActive ? Color.blue.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }
}

// MARK: - AppRuleRow

struct AppRuleRow: View {
    let rule: AppRule
    let onDelete: () -> Void

    var body: some View {
        HStack {
            if let iconData = rule.appIcon, let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading) {
                Text(rule.appName)
                    .font(.system(size: 13, weight: .medium))
                let presetName = PresetManager.shared.presets
                    .first { $0.id == rule.presetID }?.name ?? "알 수 없음"
                Text("→ \(presetName)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AddAppRuleSheet

private struct SelectedAppInfo {
    var bundleIdentifier: String
    var appName: String
    var iconData: Data?
}

struct AddAppRuleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var presetManager: PresetManager
    @ObservedObject var appSwitcherManager: AppSwitcherManager
    var onDismiss: () -> Void

    @State private var selectedApp: SelectedAppInfo?
    @State private var selectedPresetID: UUID?
    @State private var showPresetRequired = false

    var body: some View {
        VStack(spacing: 20) {
            Text("앱 규칙 추가")
                .font(.system(size: 16, weight: .bold))

            // 앱 선택
            VStack(alignment: .leading, spacing: 6) {
                Text("앱 선택")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Button {
                    pickApplication()
                } label: {
                    HStack(spacing: 10) {
                        if let app = selectedApp {
                            if let data = app.iconData, let img = NSImage(data: data) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 32, height: 32)
                            }
                            Text(app.appName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("변경")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "app.badge")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                            Text("앱을 선택하세요")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.primary.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(.primary.opacity(0.15), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // 프리셋 선택
            VStack(alignment: .leading, spacing: 6) {
                Text("적용할 프리셋")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(presetManager.presets) { preset in
                            Button {
                                selectedPresetID = preset.id
                            } label: {
                                HStack(spacing: 10) {
                                    Text(preset.emoji)
                                        .font(.system(size: 18))
                                    Text(preset.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Spacer()
                                    if selectedPresetID == preset.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedPresetID == preset.id ? Color.blue.opacity(0.12) : .primary.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }

            if showPresetRequired {
                Text("프리셋을 선택해주세요")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button("취소") {
                    onDismiss()
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("추가") {
                    guard let app = selectedApp else { return }
                    guard let presetID = selectedPresetID else {
                        showPresetRequired = true
                        return
                    }
                    let exists = appSwitcherManager.rules.contains { $0.bundleIdentifier == app.bundleIdentifier }
                    if exists {
                        // 같은 앱 규칙이 있으면 덮어쓰기 (기존 삭제 후 추가)
                        if let existing = appSwitcherManager.rules.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                            appSwitcherManager.deleteRule(id: existing.id)
                        }
                    }
                    appSwitcherManager.addRule(AppRule(
                        bundleIdentifier: app.bundleIdentifier,
                        appName: app.appName,
                        appIcon: app.iconData,
                        presetID: presetID
                    ))
                    onDismiss()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedApp == nil)
            }
        }
        .padding(24)
        .frame(width: 340, height: 420)
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.title = "앱 선택"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url) else { return }
        let bundleId = bundle.bundleIdentifier ?? url.deletingPathExtension().lastPathComponent
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let iconData = icon.tiffRepresentation
        selectedApp = SelectedAppInfo(bundleIdentifier: bundleId, appName: name, iconData: iconData)
        showPresetRequired = false
    }
}
