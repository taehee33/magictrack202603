import SwiftUI

// MARK: - TrackpadIllustration
// 감도 값에 반응하는 트랙패드 SVG 일러스트

struct TrackpadIllustration: View {
    let type: TrackpadType
    let trackingSpeed: Double   // 0.0 ~ 10.0
    let isConnected: Bool
    let accentColor: Color
    var rotation: TrackpadRotation = .standard

    @State private var pulseAnimation = false
    @State private var rippleOpacity: Double = 0

    private var cursorOffset: CGFloat {
        CGFloat((trackingSpeed / 10.0) * 18 - 9)
    }

    var body: some View {
        ZStack {
            // 트랙패드 본체
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.primary.opacity(0.08),
                            Color.primary.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isConnected ? accentColor.opacity(0.3) : Color.primary.opacity(0.1),
                            lineWidth: 1.5
                        )
                )

            if isConnected {
                // 감도 물결 애니메이션
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(accentColor.opacity(0.15 - Double(i) * 0.04), lineWidth: 1)
                        .frame(
                            width: CGFloat(20 + i * 16) * (trackingSpeed / 10.0 + 0.3),
                            height: CGFloat(20 + i * 16) * (trackingSpeed / 10.0 + 0.3)
                        )
                        .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.5 + Double(i) * 0.3)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.2),
                            value: pulseAnimation
                        )
                }

                // 커서 아이콘
                Image(systemName: "cursorarrow")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(accentColor)
                    .offset(x: cursorOffset, y: -cursorOffset * 0.5)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: trackingSpeed)

                // 연결 상태 인디케이터 (좌상단)
                VStack {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .shadow(color: .green.opacity(0.6), radius: 3)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(8)

            } else {
                // 연결 해제 상태
                VStack(spacing: 4) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 18))
                        .foregroundStyle(.tertiary)
                    Text("연결 없음")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
            }

            // 타입 라벨
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(type == .internal ? "내장" : "BT")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(4)
                }
            }
        }
        .rotationEffect(.degrees(rotation.angle))
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: rotation)
        .onAppear {
            pulseAnimation = true
        }
    }
}
