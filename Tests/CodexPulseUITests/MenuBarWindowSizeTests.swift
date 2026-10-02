import AppKit
@testable import CodexPulseUI
import Testing

@MainActor
struct MenuBarWindowSizeTests {
    private func window() -> NSWindow {
        _ = NSApplication.shared
        return NSWindow(contentRect: NSRect(x: 100, y: 100, width: 390, height: 700),
                        styleMask: [.borderless], backing: .buffered, defer: false)
    }

    private func finishUpdates() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test
    func contentChangesResizeOnlyTheOwningWindowAndKeepItsTopEdge() async {
        let panel = window()
        let unrelated = window()
        let unrelatedFrame = unrelated.frame
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let view = MenuBarWindowSizeView()
        panel.contentView?.addSubview(view)
        for height in [398.0, 675.0, 398.0] {
            view.update(size: CGSize(width: 390, height: height))
            await finishUpdates()
            #expect(panel.contentRect(forFrameRect: panel.frame).size == NSSize(width: 390, height: height))
            #expect(panel.frame.minX == topLeft.x && panel.frame.maxY == topLeft.y)
            #expect(unrelated.frame == unrelatedFrame)
        }
    }

    @Test
    func pendingUpdatesApplyLatestSizeAfterAttachment() async {
        let view = MenuBarWindowSizeView()
        view.update(size: CGSize(width: 390, height: 700))
        view.update(size: CGSize(width: 390, height: 397.5))
        let panel = window()
        panel.contentView?.addSubview(view)
        await finishUpdates()
        #expect(panel.contentRect(forFrameRect: panel.frame).size == NSSize(width: 390, height: 398))
        view.removeFromSuperview()
        view.update(size: CGSize(width: 390, height: 675))
        await finishUpdates()
        #expect(panel.contentRect(forFrameRect: panel.frame).size.height == 398)
    }

    @Test
    func invalidMeasurementsLeaveTheWindowUnchanged() async {
        let panel = window()
        let frame = panel.frame
        let view = MenuBarWindowSizeView()
        panel.contentView?.addSubview(view)
        for size in [CGSize.zero, CGSize(width: 390, height: -1),
                     CGSize(width: CGFloat.nan, height: 400), CGSize(width: 390, height: CGFloat.infinity)] {
            view.update(size: size)
            await finishUpdates()
            #expect(panel.frame == frame)
        }
    }
}
