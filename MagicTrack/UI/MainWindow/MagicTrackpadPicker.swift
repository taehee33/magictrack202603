import SwiftUI

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
