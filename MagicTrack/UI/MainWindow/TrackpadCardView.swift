import SwiftUI

// MARK: - TrackpadCardView
// 각 트랙패드(내장/매직)의 상태와 슬라이더를 표시하는 카드 컴포넌트

struct TrackpadCardView: View {
    @ObservedObject var device: TrackpadDevice
    let accentColor: Color
    /// 오른쪽에 표시할 현재 프리셋 이름 (nil이면 속도 값 표시)
    var currentPresetLabel: String? = nil
    var isCurrentlyActive: Bool = false
    var lastSwitchedAt: Date? = nil
    let onSettingChange: () -> Void
    let onActivate: () -> Void

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
                    Image(systemName: device.type.systemImageName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.type.displayName)
                        .font(.system(size: 14, weight: .semibold))
                    if isCurrentlyActive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 6, height: 6)
                            Text(activeStatusText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(accentColor)
                        }
                    } else if device.isConnected {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("연결됨 · 적용 대기")
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
                }

                Spacer()

                // 현재 프리셋 또는 속도 뱃지
                if let label = currentPresetLabel, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                } else {
                    Text(String(format: "%.1f", device.trackingSpeed))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(accentColor)
                }

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
                    TrackpadIllustration(
                        type: device.type,
                        trackingSpeed: device.trackingSpeed,
                        isConnected: device.isConnected,
                        accentColor: accentColor,
                        rotation: device.rotation
                    )
                    .frame(width: 90, height: 68)

                    // 슬라이더들 + 항목별 초기화
                    VStack(spacing: 12) {
                        HStack {
                            Button(action: onActivate) {
                                HStack(spacing: 6) {
                                    Image(systemName: isCurrentlyActive ? "checkmark.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(isCurrentlyActive ? "현재 적용 중" : "이 설정 적용")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(device.isConnected ? accentColor : Color.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(device.isConnected ? accentColor.opacity(isCurrentlyActive ? 0.18 : 0.1) : Color.primary.opacity(0.05))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!device.isConnected)
                            Spacer()
                        }

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
                                range: TrackpadDevice.speedRange,
                                accentColor: accentColor,
                                onChange: { _ in }
                            )
                            .disabled(!device.isConnected)
                            ResetButton(accentColor: accentColor, disabled: !device.isConnected) {
                                device.trackingSpeed = TrackpadDevice.defaultTrackingSpeed(for: device.type)
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
                                range: TrackpadDevice.speedRange,
                                accentColor: accentColor,
                                onChange: { _ in }
                            )
                            .disabled(!device.isConnected)
                            ResetButton(accentColor: accentColor, disabled: !device.isConnected) {
                                device.scrollSpeed = TrackpadDevice.defaultScrollSpeed(for: device.type)
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
                            ResetButton(accentColor: accentColor, disabled: !device.isConnected) {
                                device.clickPressure = TrackpadDevice.defaultClickPressure(for: device.type)
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

                                    ResetButton(accentColor: accentColor, disabled: !device.isConnected, showsMacDefaultLabel: false) {
                                        device.rotation = .standard
                                        onSettingChange()
                                    }
                                }

                                Label("현재는 UI 표시와 저장에만 반영됩니다", systemImage: "info.circle")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Label("실제 회전 입력 보정과 좌표/제스처 반영은 현재 미지원입니다", systemImage: "nosign")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
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

    private var activeStatusText: String {
        if let lastSwitchedAt {
            return "현재 적용 중 · \(lastSwitchedAt.formatted(date: .omitted, time: .standard))"
        }
        return "현재 적용 중"
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

                Text("(실험 기능 · 미지원)")
                    .font(.system(size: 10, weight: .semibold))
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
        case .standard: return "기본"
        case .left90: return "좌 90"
        case .right90: return "우 90"
        case .upsideDown: return "180"
        }
    }
}

// MARK: - ResetButton (항목별 기본값 초기화)

private struct ResetButton: View {
    let accentColor: Color
    let disabled: Bool
    var showsMacDefaultLabel: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
                Text("기본값")
                    .font(.system(size: 11, weight: .medium))
                if showsMacDefaultLabel {
                    Text("(맥 설정 값)")
                        .font(.system(size: 10, weight: .medium))
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
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("기본값으로 초기화")
    }
}
