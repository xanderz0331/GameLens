import AppKit
import AVFoundation

// MARK: - 基本参数

let W = 1080
let H = 1920
let FPS = 30
let DURATION = 18.0
let frameCount = Int(DURATION * Double(FPS))

// MARK: - 缓动 / 工具

func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }
func progress(_ t: Double, _ start: Double, _ end: Double) -> Double {
    guard end > start else { return t >= end ? 1 : 0 }
    return clamp01((t - start) / (end - start))
}
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func easeInOut(_ x: Double) -> Double {
    x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

/// 先淡入、稳住、再淡出
func fadeWindow(_ t: Double, from: Double, to: Double, outFrom: Double, outTo: Double) -> Double {
    let a = easeOut(progress(t, from, to))
    let b = easeInOut(progress(t, outFrom, outTo))
    return a * (1 - b)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let bgTop = color(0x0A0D13)
let bgBottom = color(0x171C27)
let accent = color(0x7C8CFF)
let accent2 = color(0x8A3FFC)
let inkWhite = color(0xF2F5FA)
let inkGray = color(0x9AA3B2)

// MARK: - 字体

func cnFont(_ size: CGFloat, _ weight: NSFont.Weight = .semibold) -> NSFont {
    let name: String
    switch weight {
    case .bold, .heavy, .black: name = "PingFangSC-Semibold"
    case .medium: name = "PingFangSC-Medium"
    default: name = "PingFangSC-Regular"
    }
    return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

func enFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    let name = weight >= .semibold ? "HelveticaNeue-Medium" : "HelveticaNeue"
    return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

func textWidth(_ string: String, font: NSFont) -> CGFloat {
    (string as NSString).size(withAttributes: [.font: font]).width
}

// MARK: - 绘制辅助

func drawText(_ string: String,
              font: NSFont,
              color: NSColor,
              rect: CGRect,
              alignment: NSTextAlignment = .center,
              lineSpacing: CGFloat = 8,
              shadow: NSShadow? = nil) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = lineSpacing

    var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    if let shadow { attributes[.shadow] = shadow }
    (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
}

func softShadow(_ blur: CGFloat = 18, _ dy: CGFloat = 4, _ alpha: CGFloat = 0.85) -> NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = NSSize(width: 0, height: dy)
    return shadow
}

func roundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor?, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    if let fill {
        fill.setFill()
        path.fill()
    }
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

func radialGlow(_ context: CGContext, center: CGPoint, radius: CGFloat, color: NSColor, alpha: CGFloat) {
    let colors = [color.withAlphaComponent(alpha).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                    colors: colors,
                                    locations: [0, 1]) else { return }
    context.drawRadialGradient(gradient,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: radius,
                               options: [])
}

// MARK: - 背景

func drawBackground(_ context: CGContext, _ t: Double, intensity: Double) {
    let colors = [bgTop.cgColor, bgBottom.cgColor] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: colors,
                                 locations: [0, 1]) {
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: 0),
                                   end: CGPoint(x: 0, y: CGFloat(H)),
                                   options: [])
    }

    let bokeh: [(CGFloat, CGFloat, CGFloat, NSColor, Double)] = [
        (250, 520, 420, color(0xE0A64B), 0.16),
        (860, 760, 380, color(0x3D6BE0), 0.14),
        (540, 1180, 520, color(0xC8912F), 0.10),
        (150, 1350, 300, color(0x7C8CFF), 0.10),
        (940, 300, 260, color(0xE07B4B), 0.09)
    ]
    for (x, y, r, c, a) in bokeh {
        radialGlow(context, center: CGPoint(x: x, y: y), radius: r, color: c, alpha: a * intensity)
    }

    let vignette = [
        NSColor.black.withAlphaComponent(0).cgColor,
        NSColor.black.withAlphaComponent(0).cgColor,
        NSColor.black.withAlphaComponent(0.55 * intensity).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: vignette,
                                 locations: [0, 0.55, 1]) {
        context.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2),
                                   startRadius: 200,
                                   endCenter: CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2),
                                   endRadius: 1250,
                                   options: [.drawsAfterEndLocation])
    }
}

// MARK: - 角标

func drawBrandBadge(alpha: CGFloat) {
    guard alpha > 0.01 else { return }
    let rect = CGRect(x: 72, y: 96, width: 300, height: 64)
    roundedRect(rect, radius: 32, fill: NSColor.white.withAlphaComponent(0.06 * alpha),
                stroke: NSColor.white.withAlphaComponent(0.10 * alpha))
    drawText("GameLens", font: enFont(34, .semibold), color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: rect.minX, y: rect.minY + 14, width: rect.width, height: 40))
}

/// 「开源 · 免费 · MIT」常驻角标
func drawOpenSourceBadge(_ value: CGFloat) {
    guard value > 0.01 else { return }
    let rect = CGRect(x: 72, y: 180, width: 372, height: 62)
    roundedRect(rect, radius: 31, fill: accent.withAlphaComponent(0.16 * value),
                stroke: accent.withAlphaComponent(0.55 * value), lineWidth: 1.5)
    drawText("开源 · 免费 · MIT", font: cnFont(28, .medium), color: accent.withAlphaComponent(value),
             rect: CGRect(x: rect.minX, y: rect.minY + 15, width: rect.width, height: 34))
}

// MARK: - 开场：四张字卡

/// ① 自己写了个小工具
func cardIdentity(_ t: Double) {
    let alpha = fadeWindow(t, from: 0.15, to: 0.55, outFrom: 1.30, outTo: 1.62)
    guard alpha > 0.01 else { return }
    let rise = (1 - easeOut(progress(t, 0.15, 0.6))) * 26

    drawText("自己写了个小工具", font: cnFont(76, .bold), color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: 70, y: 860 + rise, width: CGFloat(W) - 140, height: 110))

    let lineW = 120 * easeOut(progress(t, 0.45, 0.95))
    if lineW > 1 {
        let line = CGRect(x: (CGFloat(W) - lineW) / 2, y: 990 + rise, width: lineW, height: 4)
        accent.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: line, xRadius: 2, yRadius: 2).fill()
    }
}

/// ② 开源 / 免费 / 独立运行
func cardTags(_ t: Double) {
    let alpha = fadeWindow(t, from: 1.60, to: 1.95, outFrom: 2.85, outTo: 3.15)
    guard alpha > 0.01 else { return }

    let chips = ["开源", "免费", "独立运行"]
    let chipFont = cnFont(38, .medium)
    let heights: CGFloat = 78
    let gap: CGFloat = 22
    let paddings: CGFloat = 52

    let widths = chips.map { textWidth($0, font: chipFont) + paddings }
    let total = widths.reduce(0, +) + gap * CGFloat(chips.count - 1)
    var x = (CGFloat(W) - total) / 2
    let y: CGFloat = 838

    for (index, chip) in chips.enumerated() {
        let delay = 1.60 + Double(index) * 0.13
        let appear = easeOut(progress(t, delay, delay + 0.30))
        guard appear > 0.01 else { continue }

        let scale = 0.86 + 0.14 * appear
        let w = widths[index] * scale
        let rect = CGRect(x: x + (widths[index] - w) / 2, y: y + (heights - heights * scale) / 2,
                          width: w, height: heights * scale)

        roundedRect(rect, radius: heights * scale / 2,
                    fill: accent.withAlphaComponent(0.18 * appear * alpha),
                    stroke: accent.withAlphaComponent(0.65 * appear * alpha), lineWidth: 2)
        drawText(chip, font: chipFont, color: inkWhite.withAlphaComponent(appear * alpha),
                 rect: CGRect(x: rect.minX, y: rect.minY + 20, width: rect.width, height: 44))

        x += widths[index] + gap
    }

    let subAlpha = alpha * easeOut(progress(t, 2.05, 2.40))
    drawText("不用注册 · 不用订阅 · 不联网也能用", font: cnFont(34, .regular),
             color: inkGray.withAlphaComponent(subAlpha),
             rect: CGRect(x: 60, y: 975, width: CGFloat(W) - 120, height: 60))
}

/// ③ 痛点
func cardPain(_ t: Double) {
    let alpha = fadeWindow(t, from: 2.95, to: 3.30, outFrom: 4.15, outTo: 4.45)
    guard alpha > 0.01 else { return }
    let rise = (1 - easeOut(progress(t, 2.95, 3.4))) * 24

    drawText("看美剧、打游戏", font: cnFont(72, .bold), color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: 70, y: 830 + rise, width: CGFloat(W) - 140, height: 105))
    drawText("卡在一个词上，整句就断片", font: cnFont(42, .regular), color: inkGray.withAlphaComponent(alpha),
             rect: CGRect(x: 70, y: 960 + rise, width: CGFloat(W) - 140, height: 70))
}

/// ④ 转折
func cardTurn(_ t: Double) {
    let alpha = fadeWindow(t, from: 4.35, to: 4.70, outFrom: 5.30, outTo: 5.60)
    guard alpha > 0.01 else { return }
    let rise = (1 - easeOut(progress(t, 4.35, 4.8))) * 24

    drawText("所以，它先不给你中文", font: cnFont(64, .bold), color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: 70, y: 860 + rise, width: CGFloat(W) - 140, height: 100))
    drawText("卡住了，按一下，再给你", font: cnFont(40, .regular), color: accent.withAlphaComponent(alpha),
             rect: CGRect(x: 70, y: 975 + rise, width: CGFloat(W) - 140, height: 66))
}

// MARK: - 演示段

func drawEnglishSubtitle(_ t: Double) {
    let alpha = easeOut(progress(t, 5.60, 6.40)) * (1 - easeInOut(progress(t, 13.05, 13.60)))
    guard alpha > 0.01 else { return }
    let rise = (1 - easeOut(progress(t, 5.60, 6.40))) * 24

    drawText("I never asked for this, but here we are.",
             font: enFont(50), color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: 80, y: 1010 + rise, width: CGFloat(W) - 160, height: 120),
             shadow: softShadow(16, 3, 0.9 * alpha))
}

func drawQuestionBubble(_ t: Double) {
    let alpha = easeOut(progress(t, 6.60, 6.90)) * (1 - easeOut(progress(t, 7.20, 7.50)))
    guard alpha > 0.01 else { return }

    let center = CGPoint(x: 928, y: 990)
    let radius: CGFloat = 34
    let circle = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    NSColor.white.withAlphaComponent(0.12 * alpha).setFill()
    NSBezierPath(ovalIn: circle).fill()
    NSColor.white.withAlphaComponent(0.25 * alpha).setStroke()
    let path = NSBezierPath(ovalIn: circle)
    path.lineWidth = 2
    path.stroke()
    drawText("?", font: enFont(38, .semibold), color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: circle.minX, y: circle.minY + 22, width: circle.width, height: 44))
}

func drawKeyCap(_ t: Double) {
    let appear = easeOut(progress(t, 7.45, 7.75)) * (1 - easeInOut(progress(t, 13.30, 13.85)))
    guard appear > 0.01 else { return }

    let press1 = progress(t, 7.95, 8.15)
    let press2 = progress(t, 11.45, 11.65)
    let pressed = max(press1 < 1 ? sin(press1 * .pi) : 0, press2 < 1 ? sin(press2 * .pi) : 0)

    let scale = 1 - 0.08 * pressed
    let size = CGSize(width: 210, height: 130)
    let origin = CGPoint(x: CGFloat(W) - 72 - size.width, y: 88)
    let rect = CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)

    NSGraphicsContext.saveGraphicsState()
    let transform = AffineTransform(translationByX: rect.midX, byY: rect.midY)
    var scaleT = AffineTransform(scaleByX: scale, byY: scale)
    scaleT.append(transform)
    var back = transform
    back.invert()
    scaleT.append(back)
    (scaleT as NSAffineTransform).concat()

    let glow = 0.10 + 0.55 * pressed
    roundedRect(rect.insetBy(dx: -6, dy: -6), radius: 32,
                fill: accent.withAlphaComponent((0.10 + 0.30 * pressed) * appear),
                stroke: accent.withAlphaComponent(glow * appear), lineWidth: 2)
    roundedRect(rect, radius: 26, fill: NSColor.white.withAlphaComponent(0.08 * appear),
                stroke: NSColor.white.withAlphaComponent(0.18 * appear), lineWidth: 1.5)
    drawText("⌥T", font: enFont(58, .semibold), color: inkWhite.withAlphaComponent(appear),
             rect: CGRect(x: rect.minX, y: rect.midY - 34, width: rect.width, height: 70))

    NSGraphicsContext.restoreGraphicsState()
}

func drawOverlay(_ t: Double) {
    let slideIn = easeOut(progress(t, 8.00, 8.80))
    let slideOut = easeInOut(progress(t, 11.45, 12.20))
    let alpha = slideIn * (1 - slideOut)
    guard alpha > 0.01 else { return }

    let rise = (1 - slideIn) * 48 + slideOut * 36

    let width: CGFloat = 936
    let height: CGFloat = 196
    let rect = CGRect(x: (CGFloat(W) - width) / 2,
                      y: 1172 + CGFloat(rise),
                      width: width, height: height)

    roundedRect(rect, radius: 28, fill: NSColor.black.withAlphaComponent(0.72 * alpha),
                stroke: NSColor.white.withAlphaComponent(0.10 * alpha), lineWidth: 1.5)

    drawText("我从没要求过这些，但事已至此。",
             font: cnFont(50),
             color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: rect.minX + 40, y: rect.midY - 46, width: rect.width - 80, height: 92))
}

func drawCaption(_ text: String, _ alpha: Double, y: CGFloat, size: CGFloat = 38) {
    guard alpha > 0.01 else { return }
    drawText(text, font: cnFont(size, .medium), color: inkGray.withAlphaComponent(alpha),
             rect: CGRect(x: 80, y: y, width: CGFloat(W) - 160, height: 60))
}

// MARK: - 收尾

func drawOutro(_ t: Double) {
    let alpha = easeOut(progress(t, 13.70, 14.40))
    guard alpha > 0.01 else { return }

    let rise = (1 - easeOut(progress(t, 13.70, 14.50))) * 40

    let iconSize: CGFloat = 168
    let iconRect = CGRect(x: (CGFloat(W) - iconSize) / 2, y: 470 + rise, width: iconSize, height: iconSize)
    let colors = [accent.cgColor, accent2.cgColor] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                 colors: colors, locations: [0, 1]) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: iconRect, xRadius: 38, yRadius: 38).addClip()
        NSGraphicsContext.current?.cgContext.drawLinearGradient(
            gradient,
            start: CGPoint(x: iconRect.minX, y: iconRect.minY),
            end: CGPoint(x: iconRect.maxX, y: iconRect.maxY),
            options: [])
        NSGraphicsContext.restoreGraphicsState()
    }
    drawText("译", font: cnFont(96, .bold), color: NSColor(white: 0.13, alpha: alpha),
             rect: CGRect(x: iconRect.minX, y: iconRect.minY + 30, width: iconRect.width, height: 110))

    drawText("GameLens", font: enFont(78, .semibold), color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: 60, y: 680 + rise, width: CGFloat(W) - 120, height: 100))

    let tagAlpha = alpha * easeOut(progress(t, 14.05, 14.55))
    drawText("开源 · 免费 · MIT 协议", font: cnFont(38, .medium), color: accent.withAlphaComponent(tagAlpha),
             rect: CGRect(x: 60, y: 800 + rise, width: CGFloat(W) - 120, height: 60))

    let bullets = ["实时识别屏幕文字", "一键隐身，零延迟", "游戏 · 美剧 · 英文视频"]
    for (index, item) in bullets.enumerated() {
        let itemAlpha = alpha * easeOut(progress(t, 14.35 + Double(index) * 0.16, 14.95 + Double(index) * 0.16))
        drawText(item, font: cnFont(40, .medium), color: inkGray.withAlphaComponent(itemAlpha),
                 rect: CGRect(x: 60, y: 930 + CGFloat(index) * 74 + rise, width: CGFloat(W) - 120, height: 58))
    }

    let urlAlpha = alpha * easeOut(progress(t, 15.30, 15.90))
    drawText("github.com/xanderz0331/GameLens", font: enFont(34), color: accent.withAlphaComponent(urlAlpha),
             rect: CGRect(x: 60, y: 1230 + rise, width: CGFloat(W) - 120, height: 60))
}

// MARK: - 单帧合成

func renderFrame(_ t: Double, context: CGContext) {
    let outroDim = 1 - 0.55 * easeOut(progress(t, 13.5, 14.4))
    drawBackground(context, t, intensity: outroDim)

    NSGraphicsContext.saveGraphicsState()
    // NSGraphicsContext(cgContext:flipped:) 只声明坐标方向，不会真的翻转 CTM，这里手动翻
    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(H))
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

    // 常驻角标（开场字卡阶段先不出现，避免抢注意力）
    let brandAlpha = easeOut(progress(t, 5.4, 6.0)) * (1 - easeOut(progress(t, 13.5, 14.1)))
    drawBrandBadge(alpha: CGFloat(brandAlpha))

    let openSrcAlpha = easeOut(progress(t, 5.6, 6.2)) * (1 - easeOut(progress(t, 13.5, 14.1)))
    drawOpenSourceBadge(CGFloat(openSrcAlpha))

    // 开场四张卡
    cardIdentity(t)
    cardTags(t)
    cardPain(t)
    cardTurn(t)

    // 演示
    drawEnglishSubtitle(t)
    drawQuestionBubble(t)
    drawOverlay(t)

    let caption1 = easeOut(progress(t, 7.55, 8.05)) * (1 - easeOut(progress(t, 11.35, 11.75)))
    drawCaption("按一下 ⌥T，看中文翻译", caption1, y: 1440)

    let caption2 = easeOut(progress(t, 12.15, 12.65)) * (1 - easeOut(progress(t, 13.4, 13.9)))
    drawCaption("再按一下，它就藏起来 —— 先自己读", caption2, y: 1440)

    drawKeyCap(t)
    drawOutro(t)

    context.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - 编码

func renderSingle(_ t: Double) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
    ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))
    renderFrame(t, context: ctx)
    return ctx.makeImage()
}

func writeContactSheet(to url: URL, times: [Double]) {
    let cols = 3
    let rows = (times.count + cols - 1) / cols
    let cw = 480, ch = 853
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: cw * cols, height: ch * rows, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: cw * cols, height: ch * rows))
    for (index, t) in times.enumerated() {
        guard let image = renderSingle(t) else { continue }
        let col = index % cols
        let row = index / cols
        let rect = CGRect(x: CGFloat(col * cw), y: CGFloat((rows - 1 - row) * ch),
                          width: CGFloat(cw), height: CGFloat(ch))
        ctx.draw(image, in: rect)
    }
    guard let out = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: out)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
    }
}

func writeCover(to url: URL, at t: Double) {
    guard let image = renderSingle(t) else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

func makePixelBuffer(_ pool: CVPixelBufferPool) -> CVPixelBuffer? {
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
    return buffer
}

func context(for buffer: CVPixelBuffer) -> CGContext? {
    CVPixelBufferLockBaseAddress(buffer, [])
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    return CGContext(data: base,
                     width: W, height: H,
                     bitsPerComponent: 8,
                     bytesPerRow: bytesPerRow,
                     space: space,
                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
}

func writeVideo(to url: URL) -> Bool {
    try? FileManager.default.removeItem(at: url)

    guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
        print("无法创建 AVAssetWriter")
        return false
    }

    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: W,
        AVVideoHeightKey: H,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 9_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 60
        ]
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: W,
            kCVPixelBufferHeightKey as String: H
        ]
    )

    guard writer.canAdd(input) else {
        print("无法添加 input")
        return false
    }
    writer.add(input)

    guard writer.startWriting() else {
        print("startWriting 失败: \(writer.error?.localizedDescription ?? "?")")
        return false
    }
    writer.startSession(atSourceTime: .zero)

    guard let pool = adaptor.pixelBufferPool else {
        print("没有 pixelBufferPool")
        return false
    }

    print("开始渲染 \(frameCount) 帧 …")
    let started = Date()

    for frame in 0..<frameCount {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard let buffer = makePixelBuffer(pool), let ctx = context(for: buffer) else {
            print("第 \(frame) 帧缓冲创建失败")
            return false
        }

        let t = Double(frame) / Double(FPS)
        ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))
        renderFrame(t, context: ctx)
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(FPS))
        if !adaptor.append(buffer, withPresentationTime: time) {
            print("第 \(frame) 帧写入失败: \(writer.error?.localizedDescription ?? "?")")
            return false
        }

        if frame % 90 == 0 {
            let pct = Int(Double(frame) / Double(frameCount) * 100)
            print("  \(pct)%  (\(String(format: "%.1f", Date().timeIntervalSince(started)))s)")
        }
    }

    input.markAsFinished()
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting { semaphore.signal() }
    semaphore.wait()

    print("编码完成，用时 \(String(format: "%.1f", Date().timeIntervalSince(started)))s，状态 \(writer.status.rawValue)")
    return writer.status == .completed
}

// MARK: - 入口

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                     ? CommandLine.arguments[1]
                     : FileManager.default.currentDirectoryPath)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let videoURL = outputDir.appendingPathComponent("gamelens-demo-vertical.mp4")
let coverURL = outputDir.appendingPathComponent("gamelens-cover.png")

if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "--dump" {
    for t in [1.0, 2.5, 4.0, 5.0, 6.5, 7.7, 9.0, 12.0, 15.5] {
        let name = String(format: "frame-%04.1f.png", t)
        writeCover(to: outputDir.appendingPathComponent(name), at: t)
        print("写出 \(name)")
    }
    exit(0)
}

writeCover(to: coverURL, at: 9.0)
print("封面已生成: \(coverURL.path)")

writeContactSheet(to: outputDir.appendingPathComponent("contact-sheet.png"),
                  times: [0.8, 2.2, 3.6, 4.9, 6.2, 9.5, 11.0, 12.6, 16.0])
print("分镜预览已生成")

if writeVideo(to: videoURL) {
    let size: Int = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
    print("视频已生成: \(videoURL.path)")
    print("大小: \(String(format: "%.1f", Double(size) / 1024 / 1024)) MB")
} else {
    print("视频生成失败")
    exit(1)
}
