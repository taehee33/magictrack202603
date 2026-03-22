import SwiftUI

// MARK: - SensitivitySlider
// 트랙패드 유형별 색상을 가진 커스텀 슬라이더

struct SensitivitySlider: View {
    let label: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accentColor: Color
    let onChange: (Double) -> Void

    @State private var isDragging = false
    @State private var textValue: String = ""
    @FocusState private var isValueFocused: Bool

    private func commitTextInput() {
        let parsed = Double(textValue.replacingOccurrences(of: ",", with: "."))
        if let v = parsed {
            let clamped = min(max(v, range.lowerBound), range.upperBound)
            value = clamped
            onChange(clamped)
        }
        textValue = String(format: "%.1f", value)
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: 18)

                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                TextField("", text: $textValue)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isDragging ? accentColor : .primary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .textFieldStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isValueFocused ? accentColor.opacity(0.6) : Color.primary.opacity(0.2), lineWidth: 1)
                    )
                    .focused($isValueFocused)
                    .onSubmit { commitTextInput() }
                    .onChange(of: isValueFocused) { _, focused in
                        if !focused { commitTextInput() }
                    }
                    .onChange(of: value) { _, newValue in
                        if !isValueFocused { textValue = String(format: "%.1f", newValue) }
                    }
                    .onAppear { textValue = String(format: "%.1f", value) }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 배경 트랙
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.primary.opacity(0.08))
                        .frame(height: 8)

                    // 채워진 트랙
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.7), accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geo.size.width * CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)),
                            height: 8
                        )
                        .animation(.easeOut(duration: 0.1), value: value)

                    // 핸들
                    Circle()
                        .fill(.white)
                        .frame(width: isDragging ? 20 : 16, height: isDragging ? 20 : 16)
                        .shadow(color: accentColor.opacity(0.4), radius: isDragging ? 6 : 3, y: 2)
                        .overlay(
                            Circle()
                                .stroke(accentColor, lineWidth: 2)
                        )
                        .offset(
                            x: geo.size.width * CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) - (isDragging ? 10 : 8)
                        )
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isDragging = true
                            let raw = gesture.location.x / geo.size.width
                            let newValue = (range.upperBound - range.lowerBound) * Double(raw) + range.lowerBound
                            value = newValue.clamped(to: range)
                            onChange(value)
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            }
            .frame(height: 20)
        }
    }
}

// MARK: - ClickPressureSelector

struct ClickPressureSelector: View {
    @Binding var value: Int
    let accentColor: Color
    let onChange: (Int) -> Void

    private let levels = ["가볍게", "보통", "단단하게"]
    private let icons = ["hand.tap", "hand.tap.fill", "hand.tap"]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: 18)

                Text("클릭 압력")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(levels[value])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            HStack(spacing: 6) {
                ForEach(0..<3) { i in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            value = i
                            onChange(i)
                        }
                    } label: {
                        Text(levels[i])
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(value == i ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(value == i ? accentColor : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
