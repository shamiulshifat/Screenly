import AppKit
import SwiftUI

@MainActor
final class HUDNotificationManager {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(title: String, shortcut: String) {
        let content = HUDContentView(title: title, shortcut: shortcut)
        let hosting = NSHostingView(rootView: content)

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = hosting
        } else {
            panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: 96),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.contentView = hosting
            self.panel = panel
        }

        center(panel: panel)
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { [weak panel] in
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                panel?.orderOut(nil)
            }
        }
    }

    private func center(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.maxY - panel.frame.height - 80
        )
        panel.setFrameOrigin(origin)
    }
}

private struct HUDContentView: View {
    let title: String
    let shortcut: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Text(shortcut)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
