import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
