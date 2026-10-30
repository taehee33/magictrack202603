import SwiftUI

// MARK: - TrackpadCardView
// 각 트랙패드(내장/매직)의 상태와 슬라이더를 표시하는 카드 컴포넌트

struct TrackpadCardView: View {
    @ObservedObject var device: TrackpadDevice
    let accentColor: Color
    /// 지금 활성 프리셋. 이 장치 값이 프리셋과 다르면 '수정됨'을 붙인다 (nil이면 속도 값 표시)
    var activePreset: TrackpadPreset? = nil
    var isCurrentlyActive: Bool = false
    /// 두 카드를 나란히 놓을 때는 폭이 좁아 일러스트를 뺀다
    var showsIllustration: Bool = true
    let onSettingChange: () -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            // ─ 헤더 ─
            HStack(spacing: 12) {
                // 아이콘
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    // 매직 트랙패드는 놓은 방향대로 아이콘도 돌린다
                    Image(systemName: device.type.systemImageName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .rotationEffect(.degrees(device.rotation.angle))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: device.rotation)
                }
                .help(device.rotation == .standard ? "" : device.rotation.rotatedLabel)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.type.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    // 사용 중 = 지금 이 트랙패드 설정이 적용돼 있음 (전환은 위쪽 전환 모드에서)
                    HStack(spacing: 6) {
                    if isCurrentlyActive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 6, height: 6)
                            Text("사용 중")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(accentColor)
                        }
                    } else if device.isConnected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("연결됨")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 6, height: 6)
                            Text("연결 없음")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    // 돌려 놓았으면 상태 옆에 회전 방향 (예: · 180° 회전)
                    if device.rotation != .standard {
                        Text(verbatim: "· \(device.rotation.rotatedLabel)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(accentColor)
                    }
                    }
                }

                Spacer()

                // 현재 프리셋 또는 속도 뱃지
                if let preset = activePreset {
                    let modified = preset.differs(from: device)
                    HStack(spacing: 4) {
                        Text(verbatim: "\(preset.emoji) \(preset.displayName)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(accentColor)
                        if modified {
                            Text("· 수정됨")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .help(modified ? String(localized: "이 트랙패드 값이 프리셋과 달라요. 프리셋 탭에서 편집 › ‘현재 값으로 채우기’로 덮어쓸 수 있어요.") : String(localized: "지금 적용된 프리셋"))
                } else {
                    Text(String(format: "%.0f", device.trackingSpeed))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                }

                defaultsMenu

                // 펼치기/접기 버튼
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // ─ 상세 영역 ─
            if isExpanded {
                Divider().padding(.horizontal, 16)

                HStack(alignment: .top, spacing: 16) {
                    // 트랙패드 일러스트
                    if showsIllustration {
                        TrackpadIllustration(
                            type: device.type,
                            trackingSpeed: device.trackingSpeed,
                            isConnected: device.isConnected,
                            accentColor: accentColor,
                            rotation: device.rotation
                        )
                        .frame(width: 90, height: 68)
                    }

                    // 슬라이더들 + 항목별 초기화
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 8) {
                            SensitivitySlider(
                                label: "이동 속도",
                                systemImage: "cursorarrow.motionlines",
                                value: Binding(
                                    get: { device.trackingSpeed },
                                    set: { v in
                                        device.trackingSpeed = v
                                        onSettingChange()
                                    }
                                ),
                                range: TrackpadDevice.trackingRange,
                                step: 1,
                                accentColor: accentColor,
                                onChange: { _ in }
                            )
                            .disabled(!device.isConnected)
                            RevertMenu(
                                accentColor: accentColor,
                                disabled: !device.isConnected,
                                myValue: String(localized: "\(Int(device.myDefaults.trackingSpeed))칸"),
                                macValue: String(localized: "\(Int(TrackpadDefaults.mac.trackingSpeed))칸"),
                                isMyValue: device.trackingSpeed == device.myDefaults.trackingSpeed,
                                isMacValue: device.trackingSpeed == TrackpadDefaults.mac.trackingSpeed
                            ) {
                                device.trackingSpeed = device.myDefaults.trackingSpeed
                                onSettingChange()
                            } onMac: {
                                device.trackingSpeed = TrackpadDefaults.mac.trackingSpeed
                                onSettingChange()
                            }
                        }

                        HStack(alignment: .top, spacing: 8) {
                            SensitivitySlider(
                                label: "스크롤 속도",
                                systemImage: "scroll",
                                value: Binding(
                                    get: { device.scrollSpeed },
                                    set: { v in
                                        device.scrollSpeed = v
                                        onSettingChange()
                                    }
                                ),
                                range: TrackpadDevice.scrollRange,
                                step: 1,
                                accentColor: accentColor,
                                onChange: { _ in }
                            )
                            .disabled(!device.isConnected)
                            RevertMenu(
                                accentColor: accentColor,
                                disabled: !device.isConnected,
                                myValue: String(localized: "\(Int(device.myDefaults.scrollSpeed))칸"),
                                macValue: String(localized: "\(Int(TrackpadDefaults.mac.scrollSpeed))칸"),
                                isMyValue: device.scrollSpeed == device.myDefaults.scrollSpeed,
                                isMacValue: device.scrollSpeed == TrackpadDefaults.mac.scrollSpeed
                            ) {
                                device.scrollSpeed = device.myDefaults.scrollSpeed
                                onSettingChange()
                            } onMac: {
                                device.scrollSpeed = TrackpadDefaults.mac.scrollSpeed
                                onSettingChange()
                            }
                        }

                        HStack(alignment: .top, spacing: 8) {
                            ClickPressureSelector(
                                value: Binding(
                                    get: { device.clickPressure },
                                    set: { v in
                                        device.clickPressure = v
                                        onSettingChange()
                                    }
                                ),
                                accentColor: accentColor,
                                onChange: { _ in }
                            )
                            .disabled(!device.isConnected)
                            RevertMenu(
                                accentColor: accentColor,
                                disabled: !device.isConnected,
                                myValue: pressureLabel(device.myDefaults.clickPressure),
                                macValue: pressureLabel(TrackpadDefaults.mac.clickPressure),
                                isMyValue: device.clickPressure == device.myDefaults.clickPressure,
                                isMacValue: device.clickPressure == TrackpadDefaults.mac.clickPressure
                            ) {
                                device.clickPressure = device.myDefaults.clickPressure
                                onSettingChange()
                            } onMac: {
                                device.clickPressure = TrackpadDefaults.mac.clickPressure
                                onSettingChange()
                            }
                        }

                        if device.type == .magicTrackpad {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .top, spacing: 8) {
                                    RotationSelector(
                                        value: Binding(
                                            get: { device.rotation },
                                            set: { rotation in
                                                device.rotation = rotation
                                                onSettingChange()
                                            }
                                        ),
                                        accentColor: accentColor
                                    )
                                    .disabled(!device.isConnected)

                                    ResetButton(accentColor: accentColor, disabled: !device.isConnected) {
                                        device.rotation = .standard
                                        onSettingChange()
                                    }
                                }

                                RotationStatusView()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .opacity(device.isConnected ? 1 : 0.5)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    /// 카드 전체 되돌리기와 내 기본값 저장 (회전은 제외)
    private var defaultsMenu: some View {
        let current = TrackpadDefaults(trackingSpeed: device.trackingSpeed, scrollSpeed: device.scrollSpeed, clickPressure: device.clickPressure)
        return Menu {
            Section("내 기본값: \(device.myDefaults.summary)") {
                Button("모두 내 기본값으로") {
                    device.apply(device.myDefaults)
                    onSettingChange()
                }
                .disabled(current == device.myDefaults)
                Button("현재 값을 내 기본값으로 저장") {
                    device.saveAsMyDefaults()
                }
                .disabled(current == device.myDefaults)
            }
            Section("Mac 기본값: \(TrackpadDefaults.mac.summary)") {
                Button("모두 Mac 기본값으로") {
                    device.apply(.mac)
                    onSettingChange()
                }
                .disabled(current == .mac)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!device.isConnected)
        .help("기본값 되돌리기 · 내 기본값 저장")
    }

    private func pressureLabel(_ value: Int) -> String {
        TrackpadDefaults.clickPressureLabels[value.clamped(to: 0...2)]
    }

}

private struct RotationSelector: View {
    @Binding var value: TrackpadRotation
    let accentColor: Color

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rotate.3d")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: 18)

                Text("회전 방향")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(value.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            HStack(spacing: 6) {
                ForEach(TrackpadRotation.allCases, id: \.self) { rotation in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            value = rotation
                        }
                    } label: {
                        Text(rotationButtonTitle(rotation))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(value == rotation ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(value == rotation ? accentColor : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rotationButtonTitle(_ rotation: TrackpadRotation) -> String {
        switch rotation {
        case .standard: return String(localized: "기본")
        case .left90: return String(localized: "좌 90")
        case .right90: return String(localized: "우 90")
        case .upsideDown: return "180"
        }
    }
}

// MARK: - RevertMenu (항목별 기본값 되돌리기: 내 기본값 / Mac 기본값)

private struct RevertMenu: View {
    let accentColor: Color
    let disabled: Bool
    let myValue: String
    let macValue: String
    let isMyValue: Bool
    let isMacValue: Bool
    let onMine: () -> Void
    let onMac: () -> Void

    var body: some View {
        Menu {
            Button("내 기본값으로 · \(myValue)", action: onMine)
                .disabled(isMyValue)
            Button("Mac 기본값으로 · \(macValue)", action: onMac)
                .disabled(isMacValue)
        } label: {
            ResetLabel(accentColor: accentColor, disabled: disabled, showsChevron: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(disabled)
        .help("기본값으로 되돌리기")
        .accessibilityLabel("기본값으로 되돌리기")
    }
}

// MARK: - ResetButton (회전처럼 기본값이 하나뿐인 항목)

private struct ResetButton: View {
    let accentColor: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ResetLabel(accentColor: accentColor, disabled: disabled, showsChevron: false)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("기본값으로 되돌리기")
    }
}

private struct ResetLabel: View {
    let accentColor: Color
    let disabled: Bool
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12, weight: .medium))
            Text("기본값")
                .font(.system(size: 11, weight: .medium))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundStyle(disabled ? Color(nsColor: .tertiaryLabelColor) : accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(disabled ? Color.primary.opacity(0.12) : accentColor.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 회전 동작 상태와 권한 안내 (메인 창·메뉴바 공용)
struct RotationStatusView: View {
    @ObservedObject private var engine = RotationEngine.shared
    var compact = false

    var body: some View {
        if engine.needsAccessibility {
            HStack(spacing: 6) {
                Label("회전하려면 손쉬운 사용 권한이 필요해요", systemImage: "exclamationmark.triangle")
                    .font(.system(size: compact ? 11 : 10, weight: .medium))
                    .foregroundStyle(.orange)
                Button("권한 열기") { engine.requestAccessibility() }
                    .font(.system(size: compact ? 11 : 10, weight: .semibold))
                    .buttonStyle(.link)
            }
        } else if engine.driverFlipActive {
            Label("포인터·스크롤·제스처가 모두 뒤집혀요", systemImage: "checkmark.circle")
                .font(.system(size: compact ? 11 : 10, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            Label(engine.isRunning ? String(localized: "포인터·스크롤·드래그와 세·네 손가락 쓸어넘기기가 회전돼요 (두 손가락 페이지 넘기기는 제외, 손쉬운 사용 권한 사용)") : String(localized: "매직 트랙패드를 돌려 놓고 쓸 때 방향을 맞춰요"),
                  systemImage: engine.isRunning ? "checkmark.circle" : "info.circle")
                .font(.system(size: compact ? 11 : 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
