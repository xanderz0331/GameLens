import AppKit
import AVFoundation

// MARK: - 基本参数

let W = 1080
let H = 1920
let FPS = 30
let DURATION = 16.6
let frameCount = Int(DURATION * Double(FPS))

let canvas = CGRect(x: 0, y: 0, width: W, height: H)

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
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

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

    // 电影感的散景光斑
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

    // 暗角
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

// MARK: - 品牌角标

func drawBrandBadge(alpha: CGFloat) {
    guard alpha > 0.01 else { return }
    let rect = CGRect(x: 72, y: 96, width: 300, height: 64)
    roundedRect(rect, radius: 32, fill: NSColor.white.withAlphaComponent(0.06 * alpha),
                stroke: NSColor.white.withAlphaComponent(0.10 * alpha))
    drawText("GameLens", font: enFont(34, .semibold), color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: rect.minX, y: rect.minY + 14, width: rect.width, height: 40))
}

// MARK: - 场景元素

func drawEnglishSubtitle(_ t: Double) {
    let alpha = easeOut(progress(t, 3.3, 4.2))
    guard alpha > 0.01 else { return }
    let rise = (1 - easeOut(progress(t, 3.3, 4.2))) * 24

    let rect = CGRect(x: 80, y: 900 + rise, width: CGFloat(W) - 160, height: 120)
    drawText("I never asked for this, but here we are.",
             font: enFont(50), color: inkWhite.withAlphaComponent(alpha),
             rect: rect, shadow: softShadow(16, 3, 0.9 * alpha))
}

/// 「看不懂？」的小气泡
func drawQuestionBubble(_ t: Double) {
    let alpha = easeOut(progress(t, 4.55, 4.85)) * (1 - easeOut(progress(t, 5.15, 5.45)))
    guard alpha > 0.01 else { return }

    let center = CGPoint(x: 905, y: 880)
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

/// 快捷键键帽
func drawKeyCap(_ t: Double) {
    let appear = easeOut(progress(t, 5.45, 5.75))
    guard appear > 0.01 else { return }

    let press1 = progress(t, 5.95, 6.15)
    let press2 = progress(t, 9.9, 10.1)
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

/// 悬浮翻译窗
func drawOverlay(_ t: Double) {
    let slideIn = easeOut(progress(t, 6.0, 6.8))
    let slideOut = easeInOut(progress(t, 9.9, 10.6))
    let alpha = slideIn * (1 - slideOut)
    guard alpha > 0.01 else { return }

    let rise = (1 - slideIn) * 48 + slideOut * 36

    let width: CGFloat = 900
    let height: CGFloat = 196
    let rect = CGRect(x: (CGFloat(W) - width) / 2,
                      y: 1058 + CGFloat(rise),
                      width: width, height: height)

    roundedRect(rect, radius: 28, fill: NSColor.black.withAlphaComponent(0.72 * alpha),
                stroke: NSColor.white.withAlphaComponent(0.10 * alpha), lineWidth: 1.5)

    drawText("我从没要求过这些，但事已至此。",
             font: cnFont(56),
             color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: rect.minX + 40, y: rect.midY - 46, width: rect.width - 80, height: 92))
}

/// 底部解说文字
func drawCaption(_ text: String, _ alpha: Double, y: CGFloat, size: CGFloat = 38) {
    guard alpha > 0.01 else { return }
    drawText(text, font: cnFont(size, .medium), color: inkGray.withAlphaComponent(alpha),
             rect: CGRect(x: 80, y: y, width: CGFloat(W) - 160, height: 60))
}

// MARK: - 各个阶段

func drawTitleCard(_ t: Double) {
    let inA = easeOut(progress(t, 0.35, 0.95))
    let outA = progress(t, 2.85, 3.35)
    let alpha = inA * (1 - outA)
    guard alpha > 0.01 else { return }

    let rise = (1 - inA) * 34 - outA * 24

    drawText("看剧 · 打游戏", font: cnFont(92, .bold), color: inkWhite.withAlphaComponent(alpha),
             rect: CGRect(x: 60, y: 700 + rise, width: CGFloat(W) - 120, height: 130))
    drawText("学英语", font: cnFont(92, .bold), color: accent.withAlphaComponent(alpha),
             rect: CGRect(x: 60, y: 812 + rise, width: CGFloat(W) - 120, height: 130))

    drawText("先自己读，卡住再偷看", font: cnFont(42, .medium), color: inkGray.withAlphaComponent(alpha),
             rect: CGRect(x: 60, y: 1010 + rise, width: CGFloat(W) - 120, height: 70))
}

func drawOutro(_ t: Double) {
    let alpha = easeOut(progress(t, 12.2, 12.9))
    guard alpha > 0.01 else { return }

    let rise = (1 - easeOut(progress(t, 12.2, 13.0))) * 40

    // 图标
    let iconSize: CGFloat = 168
    let iconRect = CGRect(x: (CGFloat(W) - iconSize) / 2, y: 520 + rise, width: iconSize, height: iconSize)
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
             rect: CGRect(x: 60, y: 730 + rise, width: CGFloat(W) - 120, height: 100))

    let bullets = ["实时识别屏幕文字", "一键隐身，零延迟", "Apple 离线翻译，不联网也能用"]
    for (index, item) in bullets.enumerated() {
        let itemAlpha = alpha * easeOut(progress(t, 12.55 + Double(index) * 0.16, 13.15 + Double(index) * 0.16))
        drawText(item, font: cnFont(42, .medium), color: inkGray.withAlphaComponent(itemAlpha),
                 rect: CGRect(x: 60, y: 900 + CGFloat(index) * 78 + rise, width: CGFloat(W) - 120, height: 60))
    }

    let urlAlpha = alpha * easeOut(progress(t, 13.5, 14.1))
    drawText("github.com/xanderz0331/GameLens", font: enFont(34), color: accent.withAlphaComponent(urlAlpha),
             rect: CGRect(x: 60, y: 1180 + rise, width: CGFloat(W) - 120, height: 60))
}

// MARK: - 单帧合成

func renderFrame(_ t: Double, context: CGContext) {
    let outroDim = 1 - 0.55 * easeOut(progress(t, 12.0, 12.9))
    drawBackground(context, t, intensity: outroDim)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

    let brandAlpha = easeOut(progress(t, 0.8, 1.4)) * (1 - easeOut(progress(t, 12.0, 12.6)))
    drawBrandBadge(alpha: CGFloat(brandAlpha))

    drawTitleCard(t)

    // 主场景
    drawEnglishSubtitle(t)
    drawQuestionBubble(t)
    drawOverlay(t)

    // 解说
    let caption1 = easeOut(progress(t, 5.6, 6.1)) * (1 - easeOut(progress(t, 9.9, 10.3)))
    drawCaption("按一下 ⌥T，看中文翻译", caption1, y: 1330)

    let caption2 = easeOut(progress(t, 10.7, 11.2)) * (1 - easeOut(progress(t, 12.0, 12.5)))
    drawCaption("再按一下，它就藏起来 —— 先自己读", caption2, y: 1330)

    drawKeyCap(t)
    drawOutro(t)

    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - 编码

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

        if frame % 60 == 0 {
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

func writeCover(to url: URL, at t: Double) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
    ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))
    renderFrame(t, context: ctx)
    guard let image = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

// MARK: - 入口

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                     ? CommandLine.arguments[1]
                     : FileManager.default.currentDirectoryPath)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let videoURL = outputDir.appendingPathComponent("gamelens-demo-vertical.mp4")
let coverURL = outputDir.appendingPathComponent("gamelens-cover.png")

writeCover(to: coverURL, at: 8.2)
print("封面已生成: \(coverURL.path)")

if writeVideo(to: videoURL) {
    let size = (try? FileManager.default.attributesOfItem(atPath: videoURL.path)[.size] as? Int) ?? 0
    print("视频已生成: \(videoURL.path)")
    print("大小: \(String(format: "%.1f", Double(size ?? 0) / 1024 / 1024)) MB")
} else {
    print("视频生成失败")
    exit(1)
}
