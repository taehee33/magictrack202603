import SwiftUI

// MARK: - MenuBarView
// 메뉴바 팝오버 - 장치별 빠른 설정

struct MenuBarView: View {
    @EnvironmentObject var trackpadManager: TrackpadManager
    @EnvironmentObject var presetManager: PresetManager
    @Environment(\.openWindow) var openWindow
    @State private var selectedDeviceType: TrackpadType = .internal

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 12) {
                devicePicker
                menuCapabilityNotice

                ScrollView {
                    VStack(spacing: 12) {
                        if let internalTrackpad = trackpadManager.internalTrackpad {
                            CompactDeviceSection(
                                title: "내장 트랙패드",
                                icon: "laptopcomputer",
                                accentColor: .blue,
                                device: internalTrackpad,
                                trackpadManager: trackpadManager,
                                showsRotation: false,
                                isSelected: selectedDeviceType == .internal
                            )
                        }

                        if let magicTrackpad = trackpadManager.magicTrackpad {
                            CompactDeviceSection(
                                title: "매직 트랙패드",
                                icon: "rectangle.roundedtop.fill",
                                accentColor: .purple,
                                device: magicTrackpad,
                                trackpadManager: trackpadManager,
                                showsRotation: true,
                                isSelected: selectedDeviceType == .magicTrackpad
                            )
                        } else if selectedDeviceType == .magicTrackpad {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.roundedtop.fill")
                                    .foregroundStyle(.tertiary)
                                Text("선택한 트랙패드가 연결되어 있지 않습니다")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 360)
            }
            .onAppear {
                syncSelectedDeviceType()
            }
            .onChange(of: trackpadManager.magicTrackpad != nil) { _, _ in
                syncSelectedDeviceType()
            }

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presetManager.presets.prefix(4)) { preset in
                        Button {
                            presetManager.activatePreset(preset)
                        } label: {
                            HStack(spacing: 4) {
                                Text(preset.emoji)
                                    .font(.system(size: 12))
                                Text(preset.name)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(presetManager.activePresetID == preset.id
                                          ? Color.blue.opacity(0.15)
                                          : Color.primary.opacity(0.06))
                                    .overlay(
                                        Capsule()
                                            .stroke(presetManager.activePresetID == preset.id
                                                    ? Color.blue.opacity(0.4)
                                                    : .clear, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Button("열기") {
                    openWindow(id: "MagicTrack")
                    AppVisibilityManager.shared.applyCurrentDockPreference()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.blue)

                Spacer()

                Button("종료") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Image(systemName: "rectangle.roundedtop.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )
            Text("MagicTrack")
                .font(.system(size: 13, weight: .bold))
            Text(AppInfo.compactVersionDescription)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            menuShortcutHint
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var devicePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("빠른 전환 (option + M)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                menuShortcutHint
                Spacer()
            }

            HStack(spacing: 8) {
                pickerButton(
                    type: .internal,
                    title: "내장",
                    icon: "laptopcomputer",
                    color: .blue,
                    status: statusText(for: .internal),
                    isAvailable: trackpadManager.internalTrackpad != nil
                )
                pickerButton(
                    type: .magicTrackpad,
                    title: "매직",
                    icon: "rectangle.roundedtop.fill",
                    color: .purple,
                    status: statusText(for: .magicTrackpad),
                    isAvailable: trackpadManager.magicTrackpad != nil
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var menuShortcutHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.system(size: 9, weight: .semibold))
            Text("⌥M")
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func pickerButton(
        type: TrackpadType,
        title: String,
        icon: String,
        color: Color,
        status: String,
        isAvailable: Bool
    ) -> some View {
        Button {
            guard isAvailable else { return }
            selectedDeviceType = type
            trackpadManager.activateProfileManually(for: type)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isAvailable ? color : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(status)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isAvailable ? (selectedDeviceType == type ? color : .secondary) : Color(nsColor: .tertiaryLabelColor))
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedDeviceType == type ? color.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    private func statusText(for type: TrackpadType) -> String {
        let connected: Bool = {
            switch type {
            case .internal: return trackpadManager.internalTrackpad != nil
            case .magicTrackpad: return trackpadManager.magicTrackpad != nil
            }
        }()
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

    private var menuCapabilityNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            Text("수동 적용은 지원됩니다. 회전, 실입력 감지, 좌표/제스처 감지, 입력 기반 자동화는 실험/미지원 상태입니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
    }
}

private struct CompactDeviceSection: View {
    let title: String
    let icon: String
    let accentColor: Color
    @ObservedObject var device: TrackpadDevice
    let trackpadManager: TrackpadManager
    let showsRotation: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(device.isConnected ? (trackpadManager.activeTrackpadType == device.type ? accentColor : .secondary) : Color(nsColor: .tertiaryLabelColor))
                }

                Spacer()

                Button(trackpadManager.activeTrackpadType == device.type ? "적용" : "이 설정 적용") {
                    guard device.isConnected else { return }
                    trackpadManager.applySettings(for: device)
                    trackpadManager.activateProfileManually(for: device.type)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(device.isConnected ? accentColor : .secondary)
            }

            CompactSliderRow(
                label: "이동",
                value: Binding(
                    get: { device.trackingSpeed },
                    set: { value in
                        device.trackingSpeed = value
                        trackpadManager.applySettings(for: device)
                    }
                ),
                color: accentColor
            )

            CompactSliderRow(
                label: "스크롤",
                value: Binding(
                    get: { device.scrollSpeed },
                    set: { value in
                        device.scrollSpeed = value
                        trackpadManager.applySettings(for: device)
                    }
                ),
                color: accentColor
            )

            CompactPressureRow(
                value: Binding(
                    get: { device.clickPressure },
                    set: { value in
                        device.clickPressure = value
                        trackpadManager.applySettings(for: device)
                    }
                ),
                color: accentColor
            )

            if showsRotation {
                CompactRotationRow(
                    value: Binding(
                        get: { device.rotation },
                        set: { value in
                            device.rotation = value
                            device.saveSettings()
                        }
                    ),
                    color: accentColor
                )

                Text("회전은 저장/UI 표시 전용이며 실제 입력 보정은 현재 미지원")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? accentColor.opacity(0.45) : accentColor.opacity(0.18), lineWidth: 1)
                )
        )
        .opacity(device.isConnected ? 1 : 0.55)
    }

    private var statusText: String {
        guard device.isConnected else { return "연결 없음" }
        return trackpadManager.activeTrackpadType == device.type ? "연결됨 · 적용" : "연결됨 · 적용 대기"
    }
}

private struct CompactSliderRow: View {
    let label: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            Slider(value: $value, in: TrackpadDevice.speedRange)
                .tint(color)

            Text(String(format: "%.1f", value))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 28)
        }
    }
}

private struct CompactPressureRow: View {
    @Binding var value: Int
    let color: Color

    private let labels = ["가볍게", "보통", "단단하게"]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("클릭 압력")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Button {
                        value = index
                    } label: {
                        Text(labels[index])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(value == index ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(value == index ? color : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct CompactRotationRow: View {
    @Binding var value: TrackpadRotation
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("회전")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("(실험 기능 · 미지원)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(TrackpadRotation.allCases, id: \.self) { rotation in
                    Button {
                        value = rotation
                    } label: {
                        Text(title(rotation))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(value == rotation ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(value == rotation ? color : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func title(_ rotation: TrackpadRotation) -> String {
        switch rotation {
        case .standard: return "기본"
        case .left90: return "좌 90"
        case .right90: return "우 90"
        case .upsideDown: return "180"
        }
    }
}
