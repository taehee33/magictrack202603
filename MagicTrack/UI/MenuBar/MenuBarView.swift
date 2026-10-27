import SwiftUI

// MARK: - MenuBarView
// 메뉴바 팝오버 - 장치별 빠른 설정

struct MenuBarView: View {
    @EnvironmentObject var trackpadManager: TrackpadManager
    @EnvironmentObject var presetManager: PresetManager
    @Environment(\.openWindow) var openWindow
    @ObservedObject private var hotKeys = HotKeyManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 12) {
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
                                showsRotation: false
                            )
                        }

                        if let magicTrackpad = trackpadManager.magicTrackpad {
                            CompactDeviceSection(
                                title: "매직 트랙패드",
                                icon: "rectangle.roundedtop.fill",
                                accentColor: .purple,
                                device: magicTrackpad,
                                trackpadManager: trackpadManager,
                                showsRotation: true
                            )
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.roundedtop.fill")
                                    .foregroundStyle(.tertiary)
                                Text("매직 트랙패드 연결 없음")
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

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presetManager.presets) { preset in
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
            Text(AppInfo.name)
                .font(.system(size: 13, weight: .bold))
            Text(AppInfo.compactVersionDescription)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            menuShortcutHint
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 전환 모드 순환 단축키 (설정에서 끄면 숨김)
    @ViewBuilder
    private var menuShortcutHint: some View {
        if let shortcut = hotKeys.activeDisplayString {
            menuShortcutChip(shortcut)
        }
    }

    private func menuShortcutChip(_ shortcut: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.system(size: 10, weight: .semibold))
            Text(shortcut)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .help("단축키로 자동 → 내장 고정 → 매직 고정 순환")
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

    /// 전환 모드 (자동 / 내장 고정 / 매직 고정)
    private var menuCapabilityNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            if trackpadManager.switchMode == .auto && !trackpadManager.autoSwitchAvailable {
                Text("자동 감지를 쓸 수 없어 마지막 설정으로 고정돼요")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 4) {
                if let active = trackpadManager.activeTrackpadType {
                    Text("지금: \(active.displayName)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active == .internal ? Color.blue : Color.purple)
                } else {
                    Text("연결된 트랙패드 없음")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .help("앱이 켜져 있는 동안 시스템 설정보다 우선 적용돼요. 앱을 끄면 시스템 설정 값으로 돌아가요.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }
}

private struct CompactDeviceSection: View {
    let title: String
    let icon: String
    let accentColor: Color
    @ObservedObject var device: TrackpadDevice
    let trackpadManager: TrackpadManager
    let showsRotation: Bool

    private var isActive: Bool { trackpadManager.activeTrackpadType == device.type }

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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(device.isConnected ? (isActive ? accentColor : .secondary) : Color(nsColor: .tertiaryLabelColor))
                }

                Spacer()
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
                range: TrackpadDevice.trackingRange,
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
                range: TrackpadDevice.scrollRange,
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
                            trackpadManager.applySettings(for: device)
                        }
                    ),
                    color: accentColor
                )

                RotationStatusView(compact: true)
            }
        }
        .padding(10)
        .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isActive ? accentColor.opacity(0.45) : accentColor.opacity(0.18), lineWidth: 1)
                )
        )
        .opacity(device.isConnected ? 1 : 0.55)
    }

    private var statusText: String {
        guard device.isConnected else { return "연결 없음" }
        return isActive ? "사용 중" : "연결됨"
    }
}

private struct CompactSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            // 시스템 설정과 같은 칸에만 멈춤
            Slider(value: $value, in: range, step: 1)
                .tint(color)

            Text(String(format: "%.0f", value))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
                            .font(.system(size: 11, weight: .medium))
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
            }

            HStack(spacing: 4) {
                ForEach(TrackpadRotation.allCases, id: \.self) { rotation in
                    Button {
                        value = rotation
                    } label: {
                        Text(title(rotation))
                            .font(.system(size: 11, weight: .medium))
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

// MARK: - MenuBarIcon
// 메뉴바 아이콘: 앱 아이콘처럼 뒤 내장 패드 + 기울어진 앞 매직 패드. 지금 적용 중인 패드만 채워서 상태를 보여준다 (단색 템플릿)

enum MenuBarIcon {
    private static let size = NSSize(width: 20, height: 16)

    static func image(active: TrackpadType?) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            let back = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 2, width: 11, height: 8), xRadius: 2, yRadius: 2)
            let front = NSBezierPath(roundedRect: NSRect(x: -5.5, y: -4, width: 11, height: 8), xRadius: 2, yRadius: 2)
            var transform = AffineTransform(translationByX: 13.3, byY: 10)
            transform.rotate(byDegrees: -18)
            front.transform(using: transform)
            back.lineWidth = 1.4
            front.lineWidth = 1.4
            NSColor.black.set()

            if active == .internal { back.fill() } else { back.stroke() }

            // 앞 패드 자리를 비워 뒤 패드 선과 겹쳐 보이지 않게 한다
            NSGraphicsContext.current?.compositingOperation = .clear
            front.fill()
            let gap = front.copy() as! NSBezierPath
            gap.lineWidth = 3.2
            gap.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            if active == .magicTrackpad { front.fill() } else { front.stroke() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppInfo.name
        return image
    }
}
