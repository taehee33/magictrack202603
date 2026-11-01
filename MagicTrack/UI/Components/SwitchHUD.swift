import AppKit
import SwiftUI

// MARK: - SwitchHUD
// 트랙패드 프로필이나 모드가 바뀔 때 화면 아래쪽에 잠깐 보여주는 알림. 설정에서 끌 수 있다 (기본 켬)

enum SwitchHUD {
    static let enabledKey = "show_switch_hud"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static var panel: NSPanel?
    private static var hideWorkItem: DispatchWorkItem?

    /// - force: 전환 알림 설정과 상관없이 보여 줄 안내 (Dock에서 종료했을 때 등)
    static func show(title: String, subtitle: String?, force: Bool = false, duration: TimeInterval = 0.9) {
        guard isEnabled || force else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: HUDView(title: title, subtitle: subtitle))
        let size = panel.contentView?.fittingSize ?? NSSize(width: 200, height: 56)
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.minY + 80, width: size.width, height: size.height), display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWorkItem?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
                panel.orderOut(nil)
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.hasShadow = false
        return panel
    }

    private struct HUDView: View {
        let title: String
        let subtitle: String?

        var body: some View {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .fixedSize()
        }
    }
}
