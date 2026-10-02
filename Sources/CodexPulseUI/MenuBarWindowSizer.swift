import AppKit
import SwiftUI

/// MenuBarExtra 切换内容时可能保留旧高度，只调整此面板所在的窗口。
struct MenuBarWindowSizer: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> MenuBarWindowSizeView { MenuBarWindowSizeView() }

    func updateNSView(_ view: MenuBarWindowSizeView, context: Context) { view.update(size: size) }
}

final class MenuBarWindowSizeView: NSView {
    private var contentSize = CGSize.zero
    private var updateScheduled = false

    func update(size: CGSize) {
        contentSize = size
        scheduleUpdate()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleUpdate()
    }

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        // 等当前布局结束，合并同一轮更新，并在视图挂入窗口后应用最新尺寸。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            guard let window = self.window, self.contentSize.width.isFinite, self.contentSize.height.isFinite,
                  self.contentSize.width > 0, self.contentSize.height > 0 else { return }
            let size = NSSize(width: ceil(self.contentSize.width), height: ceil(self.contentSize.height))
            guard window.contentRect(forFrameRect: window.frame).size != size else { return }
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            window.setContentSize(size)
            window.setFrameTopLeftPoint(topLeft)
        }
    }
}
