import SwiftUI
import AppKit

// MARK: - PresetEditorTarget
// 편집 시트에 넘길 프리셋 (새로 만들기 / 고치기)

struct PresetEditorTarget: Identifiable {
    let preset: TrackpadPreset
    let isNew: Bool
    var id: UUID { preset.id }
}

// MARK: - PresetEditorSheet
// 프리셋 만들기·편집: 이름, 이모지, 두 트랙패드의 이동·스크롤·클릭 압력 (매직은 회전 포함)

struct PresetEditorSheet: View {
    @ObservedObject var presetManager: PresetManager
    let isNew: Bool
    let onDismiss: () -> Void

    @State private var draft: TrackpadPreset

    private static let emojis = [
        "☀️", "💻", "🎨", "🎮", "📝", "🎬", "🎧", "📊", "✏️", "📚", "🧪", "🎵",
        "📷", "🛠️", "🚀", "⚡", "🔥", "🌙", "🏠", "🏢", "✈️", "☕️", "⭐️", "❤️"
    ]

    init(presetManager: PresetManager, target: PresetEditorTarget, onDismiss: @escaping () -> Void) {
        self.presetManager = presetManager
        self.isNew = target.isNew
        self.onDismiss = onDismiss
        _draft = State(initialValue: target.preset)
    }

    private var trimmedName: String {
        draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "새 프리셋" : "프리셋 편집")
                .font(.system(size: 16, weight: .bold))

            HStack(spacing: 10) {
                TextField("", text: emojiBinding)
                    .font(.system(size: 22))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .help("이모지 (기타 이모지는 아래 '기타…')")
                TextField("프리셋 이름", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }

            emojiGrid

            HStack(alignment: .top, spacing: 16) {
                deviceSection(.internal, title: "내장 트랙패드", icon: "laptopcomputer", color: .blue)
                deviceSection(.magicTrackpad, title: "매직 트랙패드", icon: "rectangle.roundedtop.fill", color: .purple)
            }

            if !isNew && presetManager.activePresetID == draft.id {
                Label("지금 사용 중인 프리셋이라 저장하면 바로 적용돼요.", systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("현재 값으로 채우기") {
                    let current = presetManager.presetFromCurrentSettings()
                    draft.setValues(current.values(for: .internal), for: .internal)
                    draft.setValues(current.values(for: .magicTrackpad), for: .magicTrackpad)
                    draft.magicRotation = current.magicRotation
                }
                .help("두 트랙패드의 지금 설정으로 값을 채워요")

                Spacer()

                Button("취소", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Button("저장") {
                    var preset = draft
                    preset.name = trimmedName
                    presetManager.save(preset)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 580)
    }

    /// 이모지는 한 글자만 남긴다 (시스템 이모지 창으로 넣어도 마지막 하나만)
    private var emojiBinding: Binding<String> {
        Binding(
            get: { draft.emoji },
            set: { newValue in
                if let last = newValue.last { draft.emoji = String(last) }
            }
        )
    }

    private var emojiGrid: some View {
        HStack(alignment: .top, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 12), spacing: 4) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button {
                        draft.emoji = emoji
                    } label: {
                        Text(emoji)
                            .font(.system(size: 18))
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(draft.emoji == emoji ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("기타…") {
                NSApp.orderFrontCharacterPalette(nil)
            }
            .controlSize(.small)
            .help("시스템 이모지 창 (이모지 칸을 누른 뒤 고르세요)")
        }
    }

    private func deviceSection(_ type: TrackpadType, title: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)

            valueSlider("이동 속도", keyPath: \.trackingSpeed, range: TrackpadDevice.trackingRange, type: type, color: color)
            valueSlider("스크롤 속도", keyPath: \.scrollSpeed, range: TrackpadDevice.scrollRange, type: type, color: color)

            VStack(alignment: .leading, spacing: 4) {
                Text("클릭 압력")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: valueBinding(\.clickPressure, type: type)) {
                    ForEach(0..<3, id: \.self) { level in
                        Text(TrackpadDefaults.clickPressureLabels[level]).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if type == .magicTrackpad {
                VStack(alignment: .leading, spacing: 4) {
                    Text("회전")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $draft.magicRotation) {
                        ForEach(TrackpadRotation.allCases, id: \.self) { rotation in
                            Text(rotation.displayName).tag(rotation)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.06)))
    }

    private func valueSlider(_ label: String, keyPath: WritableKeyPath<TrackpadDefaults, Double>, range: ClosedRange<Double>,
                             type: TrackpadType, color: Color) -> some View {
        let binding = valueBinding(keyPath, type: type)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(binding.wrappedValue))칸")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }
            Slider(value: binding, in: range, step: 1)
                .tint(color)
        }
    }

    private func valueBinding<Value>(_ keyPath: WritableKeyPath<TrackpadDefaults, Value>, type: TrackpadType) -> Binding<Value> {
        Binding(
            get: { draft.values(for: type)[keyPath: keyPath] },
            set: { newValue in
                var values = draft.values(for: type)
                values[keyPath: keyPath] = newValue
                draft.setValues(values, for: type)
            }
        )
    }
}
