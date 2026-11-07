import AppKit

private final class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class PickerView: NSView {
    var onFinish: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else { return nil }
        return NSRect(x: min(startPoint.x, currentPoint.x),
                      y: min(startPoint.y, currentPoint.y),
                      width: abs(currentPoint.x - startPoint.x),
                      height: abs(currentPoint.y - startPoint.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.35)
        if let rect = selectionRect {
            dim.setFill()
            let strips = [
                NSRect(x: 0, y: 0, width: bounds.width, height: rect.minY),
                NSRect(x: 0, y: rect.maxY, width: bounds.width, height: bounds.height - rect.maxY),
                NSRect(x: 0, y: rect.minY, width: rect.minX, height: rect.height),
                NSRect(x: rect.maxX, y: rect.minY, width: bounds.width - rect.maxX, height: rect.height)
            ]
            for strip in strips where strip.width > 0 && strip.height > 0 {
                strip.fill()
            }

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2
            border.stroke()

            NSColor.systemBlue.withAlphaComponent(0.16).setFill()
            rect.fill(using: .sourceOver)

            let label = "\(Int(rect.width)) × \(Int(rect.height))"
            drawCentered(label,
                         in: NSRect(x: rect.minX, y: max(8, rect.minY - 30), width: rect.width, height: 22),
                         size: 12,
                         weight: .semibold)
        } else {
            dim.setFill()
            bounds.fill()
        }

        drawCentered("拖动鼠标框选「游戏台词区域」  ·  Esc 取消",
                     in: NSRect(x: 0, y: bounds.height - 64, width: bounds.width, height: 26),
                     size: 17,
                     weight: .semibold)
    }

    private func drawCentered(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = .zero

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]
        NSAttributedString(string: text, attributes: attributes)
            .draw(in: rect)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let rect = selectionRect, rect.width > 40, rect.height > 18 else {
            onCancel?()
            return
        }
        onFinish?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class RegionPickerController {
    private var windows: [NSWindow] = []
    private(set) var isActive = false
    private var completion: ((CaptureRegion?) -> Void)?

    func begin(completion: @escaping (CaptureRegion?) -> Void) {
        guard !isActive else { return }
        self.completion = completion
        isActive = true

        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let window = PickerWindow(contentRect: screen.frame,
                                      styleMask: .borderless,
                                      backing: .buffered,
                                      defer: false,
                                      screen: screen)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onCancel = { [weak self] in self?.finish(nil) }
            view.onFinish = { [weak self, weak window] localRect in
                guard let self, let window else { return }
                let global = NSRect(x: localRect.minX + window.frame.minX,
                                    y: localRect.minY + window.frame.minY,
                                    width: localRect.width,
                                    height: localRect.height)
                let hostScreen = window.screen ?? screen
                self.finish(CaptureRegion.make(screen: hostScreen, globalRect: global))
            }

            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            windows.append(window)
        }
    }

    func finish(_ region: CaptureRegion?) {
        guard isActive else { return }
        isActive = false
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        NSApp.activate(ignoringOtherApps: false)
        let callback = completion
        completion = nil
        callback?(region)
    }

    func cancel() {
        finish(nil)
    }
}
