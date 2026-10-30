import SwiftUI
import AppKit

// MARK: - MainView

struct MainView: View {
    @EnvironmentObject var trackpadManager: TrackpadManager
    @EnvironmentObject var presetManager: PresetManager
    @EnvironmentObject var appSwitcherManager: AppSwitcherManager
    @ObservedObject private var hotKeys = HotKeyManager.shared

    /// ⌘,로 창을 새로 열 때 설정 탭으로 시작하게 한다 (이미 열린 창은 알림으로 바꾼다)
    static var opensSettingsOnAppear = false

    @State private var editingPreset: PresetEditorTarget?
    @State private var deletingPreset: TrackpadPreset?
    @State private var showBluetoothPickerSheet = false
    @State private var selectedTab: Tab = .devices
    @State private var devicesTabWidth: CGFloat = 0
    @AppStorage(DeveloperMode.key) private var developerMode = false

    enum Tab: String, CaseIterable {
        case devices = "트랙패드"
        case presets = "프리셋"
        case settings = "설정"

        var title: String {
            switch self {
            case .devices: return String(localized: "트랙패드")
            case .presets: return String(localized: "프리셋")
            case .settings: return String(localized: "설정")
            }
        }

        var icon: String {
            switch self {
            case .devices: return "rectangle.roundedtop.fill"
            case .presets: return "slider.horizontal.3"
            case .settings: return "gearshape"
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
                case .settings:
                    SettingsView()
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
        .sheet(item: $editingPreset) { target in
            PresetEditorSheet(presetManager: presetManager, target: target) {
                editingPreset = nil
            }
        }
        .sheet(isPresented: $showBluetoothPickerSheet) {
            BluetoothDevicePickerSheet(
                trackpadManager: trackpadManager,
                onDismiss: { showBluetoothPickerSheet = false }
            )
        }
        .onAppear {
            if Self.opensSettingsOnAppear {
                Self.opensSettingsOnAppear = false
                selectedTab = .settings
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsTab)) { _ in
            Self.opensSettingsOnAppear = false
            selectedTab = .settings
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            // 앱 아이콘 (아이콘 이미지는 1024 중 824만 몸체라 52로 그리면 몸체가 약 42)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)
                .padding(-5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(AppInfo.name)
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
                        Text(tab.title)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(selectedTab == tab ? Color.primary.opacity(0.12) : .clear)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab)
                    )
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
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
                switchModeBar

                // 폭이 넉넉하면 두 트랙패드를 나란히 놓아 한눈에 보이게 한다
                if devicesTabWidth >= Self.sideBySideMinWidth {
                    HStack(alignment: .top, spacing: 14) {
                        internalCard(showsIllustration: false)
                            .frame(maxWidth: .infinity)
                        magicSection(showsIllustration: false)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    internalCard(showsIllustration: true)
                    magicSection(showsIllustration: true)
                }

                // 현재 설정 저장 버튼
                Button {
                    editingPreset = PresetEditorTarget(preset: presetManager.presetFromCurrentSettings(), isNew: true)
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

                if developerMode {
                    inputDebugPanel
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { devicesTabWidth = $0 }
    }

    /// 카드 둘을 나란히 놓는 최소 폭 (카드 하나에 슬라이더가 충분히 들어가는 폭 × 2 + 여백)
    private static let sideBySideMinWidth: CGFloat = 820

    private func internalCard(showsIllustration: Bool) -> some View {
        TrackpadCardView(
            device: internalDevice,
            accentColor: .blue,
            activePreset: presetManager.activePreset,
            isCurrentlyActive: trackpadManager.activeTrackpadType == .internal,
            showsIllustration: showsIllustration
        ) {
            guard trackpadManager.internalTrackpad != nil else { return }
            trackpadManager.applySettings(for: internalDevice)
        }
    }

    @ViewBuilder
    private func magicSection(showsIllustration: Bool) -> some View {
        if let magic = magicDevice {
            VStack(spacing: 8) {
                TrackpadCardView(
                    device: magic,
                    accentColor: .purple,
                    activePreset: presetManager.activePreset,
                    isCurrentlyActive: trackpadManager.activeTrackpadType == .magicTrackpad,
                    showsIllustration: showsIllustration
                ) {
                    trackpadManager.applySettings(for: magic)
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
    }

    /// 전환 모드 순환 단축키 (설정에서 끄면 숨김)
    @ViewBuilder
    private var shortcutHint: some View {
        if let shortcut = hotKeys.activeDisplayString {
            shortcutChip(shortcut)
        }
    }

    private func shortcutChip(_ shortcut: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.system(size: 10, weight: .semibold))
            Text(shortcut)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .help("단축키로 자동 → 내장 고정 → 매직 고정 순환")
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

    private var inputDebugPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("장치·전환 로그")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("터치 감지와 프로필 전환 기록")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    debugCountPill(title: "CONNECT", count: trackpadManager.hidConnectCount, color: .blue)
                    debugCountPill(title: "TOUCH", count: trackpadManager.hidMonitorCount, color: .blue)
                    debugCountPill(title: "ACTIVATE", count: trackpadManager.hidActivateCount, color: .blue)
                }
            }

            Text("TOUCH는 새 터치가 시작된 횟수, ACTIVATE는 프로필이 적용된 횟수예요. 터치 감지 \(trackpadManager.autoSwitchAvailable ? String(localized: "사용 가능") : String(localized: "사용 불가"))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if trackpadManager.recentInputLogs.isEmpty {
                Text("아직 기록이 없습니다")
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
                                Text("\(log.trackpadType?.displayName ?? String(localized: "미분류")) · \(log.deviceName)")
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

    /// 전환 모드 (자동 / 내장 고정 / 매직 고정). 빠른 전환 버튼과 '이 설정 적용'도 결국 고정 모드라 여기 하나로 합쳤다
    private var switchModeBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("전환 모드")
                    .font(.system(size: 12, weight: .semibold))

                Picker("", selection: Binding(
                    get: { trackpadManager.switchMode },
                    set: { trackpadManager.setSwitchMode($0) }
                )) {
                    ForEach(SwitchMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                shortcutHint

                Spacer(minLength: 8)

                activeTrackpadBadge
            }

            HStack(spacing: 4) {
                Text(switchModeDescription)
                    .foregroundStyle(trackpadManager.switchMode == .auto && !trackpadManager.autoSwitchAvailable ? .orange : .secondary)
                Image(systemName: "info.circle")
                    .foregroundStyle(.tertiary)
                    .help("\(AppInfo.name)이 켜져 있는 동안에는 여기 설정이 시스템 설정보다 우선 적용돼요. 앱을 끄면 시스템 설정 값으로 돌아가요. 시스템 설정에 저장된 값은 바꾸지 않아요.")
            }
            .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    /// 지금 설정이 적용된 트랙패드 (내장 파랑 / 매직 보라)
    @ViewBuilder
    private var activeTrackpadBadge: some View {
        if let active = trackpadManager.activeTrackpadType {
            let color: Color = active == .internal ? .blue : .purple
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text("지금: \(active.displayName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            .help(trackpadManager.lastActiveSwitchAt.map { String(localized: "마지막 전환 \($0.formatted(date: .omitted, time: .standard))") } ?? "")
        } else {
            Text("연결된 트랙패드 없음")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var switchModeDescription: String {
        switch trackpadManager.switchMode {
        case .auto where !trackpadManager.autoSwitchAvailable:
            return String(localized: "자동 감지를 쓸 수 없어 마지막 설정으로 고정돼요")
        case .auto:
            return String(localized: "손가락이 닿은 트랙패드의 설정으로 바로 바뀌어요")
        case .lockInternal, .lockMagic:
            return String(localized: "어느 트랙패드를 써도 \(trackpadManager.switchMode.lockedType?.displayName ?? "") 설정을 유지해요")
        }
    }

    // MARK: - Presets Tab

    private var presetsTab: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(presetManager.presets) { preset in
                    PresetCardView(
                        preset: preset,
                        isActive: presetManager.activePresetID == preset.id,
                        ruleCount: appSwitcherManager.rules(usingPreset: preset.id).count
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            presetManager.activatePreset(preset)
                        }
                    } onEdit: {
                        editingPreset = PresetEditorTarget(preset: preset, isNew: false)
                    } onDuplicate: {
                        presetManager.duplicatePreset(id: preset.id)
                    } onDelete: {
                        deletingPreset = preset
                    }
                }

                // 새 프리셋 추가 버튼 (지금 값으로 채워서 연다)
                Button {
                    editingPreset = PresetEditorTarget(preset: presetManager.presetFromCurrentSettings(), isNew: true)
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
        .confirmationDialog(
            deletingPreset.map { String(localized: "‘\($0.emoji) \($0.displayName)’ 프리셋을 삭제할까요?") } ?? "",
            isPresented: Binding(get: { deletingPreset != nil }, set: { if !$0 { deletingPreset = nil } }),
            presenting: deletingPreset
        ) { preset in
            let ruleCount = appSwitcherManager.rules(usingPreset: preset.id).count
            if ruleCount > 0 {
                Button("프리셋과 앱 규칙 \(ruleCount)개 삭제", role: .destructive) {
                    presetManager.deletePreset(id: preset.id, removingRules: true)
                }
                Button("프리셋만 삭제") {
                    presetManager.deletePreset(id: preset.id)
                }
            } else {
                Button("삭제", role: .destructive) {
                    presetManager.deletePreset(id: preset.id)
                }
            }
            Button("취소", role: .cancel) {}
        } message: { preset in
            let ruleCount = appSwitcherManager.rules(usingPreset: preset.id).count
            Text(ruleCount > 0
                 ? String(localized: "이 프리셋을 쓰는 앱 규칙이 \(ruleCount)개 있어요. 프리셋만 지우면 그 규칙은 ‘프리셋 없음’으로 남아요. 되돌릴 수 없어요.")
                 : String(localized: "되돌릴 수 없어요."))
        }
    }

}
