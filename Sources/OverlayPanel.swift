import AppKit

/// 悬浮字幕窗：置顶、鼠标穿透、不抢游戏焦点。
final class OverlayView: NSView {
    var sourceText: String = "" { didSet { needsDisplay = true } }
    var targetText: String = "" { didSet { needsDisplay = true } }

    var fontSize: CGFloat = 30
    var showSource: Bool = true
    var backgroundOpacity: CGFloat = 0.66

    let horizontalPadding: CGFloat = 16
    let verticalPadding: CGFloat = 12
    let lineGap: CGFloat = 6
    let cornerRadius: CGFloat = 14

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    var targetAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
    }

    var sourceAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left
        return [
            .font: NSFont.systemFont(ofSize: max(11, fontSize * 0.56), weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.62),
            .paragraphStyle: paragraph
        ]
    }

    private func measure(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 8 else { return 0 }
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let bounds = attributed.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(bounds.height)
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        let innerWidth = max(40, width - horizontalPadding * 2)
        var total = verticalPadding * 2

        if showSource, !sourceText.isEmpty {
            total += measure(sourceText, attributes: sourceAttributes, width: innerWidth) + lineGap
        }
        if !targetText.isEmpty {
            total += measure(targetText, attributes: targetAttributes, width: innerWidth)
        }
        return max(verticalPadding * 2 + fontSize, total)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.withAlphaComponent(backgroundOpacity).setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.10).setStroke()
        path.lineWidth = 1
        path.stroke()

        let innerWidth = bounds.width - horizontalPadding * 2
        var cursorY = verticalPadding

        if showSource, !sourceText.isEmpty {
            let attributes = sourceAttributes
            let height = measure(sourceText, attributes: attributes, width: innerWidth)
            NSAttributedString(string: sourceText, attributes: attributes)
                .draw(with: NSRect(x: horizontalPadding, y: cursorY, width: innerWidth, height: height),
                      options: [.usesLineFragmentOrigin, .usesFontLeading])
            cursorY += height + lineGap
        }

        if !targetText.isEmpty {
            let attributes = targetAttributes
            let height = measure(targetText, attributes: attributes, width: innerWidth)
            NSAttributedString(string: targetText, attributes: attributes)
                .draw(with: NSRect(x: horizontalPadding, y: cursorY, width: innerWidth, height: height),
                      options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
    }
}

final class OverlayPanel: NSPanel {
    let overlayView = OverlayView()

    private(set) var isShowing = false
    private var region: CaptureRegion?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 90),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        alphaValue = 1
        contentView = overlayView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(source: String, target: String, region: CaptureRegion?, settings: Settings) {
        overlayView.sourceText = source
        overlayView.targetText = target
        overlayView.fontSize = CGFloat(settings.fontSize)
        overlayView.showSource = settings.showSource
        overlayView.backgroundOpacity = CGFloat(settings.backgroundOpacity)
        if let region { self.region = region }
        relayout()
    }

    func clear() {
        overlayView.sourceText = ""
        overlayView.targetText = ""
        relayout()
    }

    func relayout() {
        guard let region else { return }
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(region.globalRect) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? region.globalRect

        let targetWidth = clamp(region.globalRect.width * 1.18, 260, 1500)
        let height = overlayView.height(forWidth: targetWidth)

        var x = region.globalRect.midX - targetWidth / 2
        var y = region.globalRect.minY - height - 10

        if y < visible.minY + 6 {
            y = region.globalRect.maxY + 10
        }
        if y + height > visible.maxY - 6 {
            y = max(visible.minY + 6, visible.maxY - height - 6)
        }
        x = clamp(x, visible.minX + 6, visible.maxX - targetWidth - 6)

        setFrame(NSRect(x: x, y: y, width: targetWidth, height: height), display: true)
    }

    func show(animated: Bool = true) {
        isShowing = true
        relayout()
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                animator().alphaValue = 1
            }
        } else {
            alphaValue = 1
        }
    }

    func hide() {
        isShowing = false
        orderOut(nil)
    }
}
