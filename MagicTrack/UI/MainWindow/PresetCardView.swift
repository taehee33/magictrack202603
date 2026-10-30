import SwiftUI

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
