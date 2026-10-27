import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                    .keyboardShortcut(.cancelAction)
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
                                        Text(device.kind.displayName)
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
                                Button(trackpadManager.preferredBluetoothDeviceKey == device.id ? String(localized: "선택됨") : String(localized: "선택")) {
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
    let ruleCount: Int
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onActivate) {
            VStack(alignment: .leading, spacing: 8) {
                Text(preset.emoji)
                    .font(.system(size: 22))

                HStack(spacing: 6) {
                    Text(preset.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 12))
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 10))
                    Text("\(Int(preset.internalTrackingSpeed))칸")
                    Text("·")
                    Image(systemName: "rectangle.roundedtop.fill")
                        .font(.system(size: 10))
                    Text("\(Int(preset.magicTrackingSpeed))칸")
                    if ruleCount > 0 {
                        Text("·")
                        Image(systemName: "app.badge")
                            .font(.system(size: 10))
                        Text("앱 \(ruleCount)")
                    }
                }
                .font(.system(size: 11, design: .rounded))
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
        .overlay(alignment: .topTrailing) {
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(8)
            .help("편집 · 복제 · 삭제")
        }
        .contextMenu { menuItems }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("편집…", action: onEdit)
        Button("복제", action: onDuplicate)
        Divider()
        Button("삭제…", role: .destructive, action: onDelete)
    }
}

// MARK: - AppRuleRow

struct AppRuleRow: View {
    let rule: AppRule
    let onChangePreset: (UUID) -> Void
    let onDelete: () -> Void
    @ObservedObject private var presetManager = PresetManager.shared

    var body: some View {
        let preset = presetManager.presets.first { $0.id == rule.presetID }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.appName)
                    .font(.system(size: 13, weight: .medium))
                if preset == nil {
                    Label("프리셋이 없어요. 오른쪽에서 다시 골라 주세요.", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            // 적용할 프리셋 바꾸기 (프리셋이 지워진 규칙도 여기서 고친다)
            Menu(preset.map { "\($0.emoji) \($0.displayName)" } ?? String(localized: "프리셋 고르기")) {
                ForEach(presetManager.presets) { option in
                    Button(String("\(option.emoji) \(option.displayName)")) { onChangePreset(option.id) }
                }
            }
            .fixedSize()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("규칙 삭제")
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
                                    Text(preset.displayName)
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
                .keyboardShortcut(.cancelAction)

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
                .keyboardShortcut(.defaultAction)
                .disabled(selectedApp == nil)
            }
        }
        .padding(24)
        .frame(width: 340, height: 420)
    }

    private func pickApplication() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "앱 선택")
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
