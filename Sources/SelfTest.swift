import AppKit
import Foundation
import Vision
#if canImport(Translation)
import Translation
#endif

enum SelfTest {
    static func run() async -> Bool {
        var passed = true
        print("=== GameLens 自检 ===")

        guard let image = makeTestImage() else {
            print("❌ 无法生成测试图片")
            return false
        }

        do {
            let started = Date()
            let result = try OCR.recognize(image)
            let elapsed = Date().timeIntervalSince(started) * 1000
            print(String(format: "OCR (%d×%d, %.0fms) → %@", image.width, image.height, elapsed, result.text))
            if normalizeForCompare(result.text).contains("never asked") {
                print("✅ Vision OCR 正常")
            } else {
                print("❌ OCR 结果与预期不符")
                passed = false
            }
        } catch {
            print("❌ OCR 失败：\(error.localizedDescription)")
            passed = false
        }

        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            let availability = LanguageAvailability()
            let status = await availability.status(from: Locale.Language(identifier: "en"),
                                                   to: Locale.Language(identifier: "zh-Hans"))
            print("· Apple 离线翻译 en → zh-Hans 状态：\(status)")
            if status == .installed {
                do {
                    let output = try await AppleOfflineEngine().translate("I never asked for this, but here we are.",
                                                                          source: "en",
                                                                          target: "zh-Hans",
                                                                          notes: false)
                    print("✅ Apple 离线翻译可用 → \(output)")
                } catch {
                    print("❌ Apple 离线翻译报错：\(error.localizedDescription)")
                    passed = false
                }
            } else {
                print("· Apple 离线翻译语言包未安装（App 会自动回退到在线引擎）")
            }
        }
        #endif

        do {
            let output = try await GoogleEngine().translate("I never asked for this, but here we are.",
                                                            source: "en",
                                                            target: "zh-Hans",
                                                            notes: false)
            print("✅ Google 在线翻译正常 → \(output)")
        } catch {
            print("⚠️ Google 在线翻译失败（可能是网络限制）：\(error.localizedDescription)")
        }

        print(passed ? "=== 自检通过 ===" : "=== 自检存在失败项 ===")
        return passed
    }

    static func makeTestImage() -> CGImage? {
        let size = NSSize(width: 720, height: 150)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30, weight: .regular),
            .foregroundColor: NSColor.white
        ]
        NSString(string: "I never asked for this, but here we are.")
            .draw(in: NSRect(x: 26, y: 56, width: 668, height: 46), withAttributes: attributes)
        image.unlockFocus()

        var proposed = NSRect(origin: .zero, size: size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    static func renderOverlay(to path: String) -> Bool {
        let width: CGFloat = 640
        let view = OverlayView(frame: NSRect(x: 0, y: 0, width: width, height: 120))
        view.sourceText = "I never asked for this, but here we are."
        view.targetText = "我从没要求过这些，但事已至此。"
        view.fontSize = 30
        view.showSource = true
        view.backgroundOpacity = 0.66

        let height = view.height(forWidth: width)
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("已渲染悬浮窗预览：\(path)  (\(Int(width))×\(Int(height)))")
            return true
        } catch {
            print("写入失败：\(error.localizedDescription)")
            return false
        }
    }


    static func benchOCR() -> Bool {
        guard let image = makeTestImage() else { return false }
        for level in [VNRequestTextRecognitionLevel.fast, .accurate] {
            var times: [Double] = []
            var last = ""
            for _ in 0..<5 {
                let started = Date()
                if let result = try? OCR.recognize(image, level: level) {
                    last = result.text
                }
                times.append(Date().timeIntervalSince(started) * 1000)
            }
            let avg = times.reduce(0, +) / Double(times.count)
            let name = level == .fast ? "fast    " : "accurate"
            print(String(format: "%@ 平均 %.0fms  最小 %.0fms → %@",
                         name, avg, times.min() ?? 0, last))
        }
        return true
    }

    static func translate(_ text: String) async -> Bool {
        let settings = Settings.shared
        let engine = EngineFactory.shared.engine(for: settings)
        print("引擎：\(engine.displayName)")
        do {
            let output = try await engine.translate(text,
                                                    source: settings.sourceLanguage,
                                                    target: settings.targetLanguage,
                                                    notes: settings.showNotes && engine.supportsNotes)
            print(output)
            return true
        } catch {
            print("翻译失败：\(error.localizedDescription)")
            return false
        }
    }
}

enum CLI {
    /// 返回 true 表示走的是命令行模式，不需要启动图形界面。
    static func handleIfNeeded(_ arguments: [String]) -> Bool {
        guard arguments.count > 1 else { return false }

        if arguments.contains("--selftest") {
            _ = NSApplication.shared
            Task {
                let ok = await SelfTest.run()
                exit(ok ? 0 : 1)
            }
            return true
        }

        if let index = arguments.firstIndex(of: "--render-overlay"), arguments.count > index + 1 {
            _ = NSApplication.shared
            exit(SelfTest.renderOverlay(to: arguments[index + 1]) ? 0 : 2)
        }

        if arguments.contains("--diagnose") {
            _ = NSApplication.shared
            Task {
                await Diagnostics.run()
                exit(0)
            }
            return true
        }

        if arguments.contains("--ocr-bench") {
            _ = NSApplication.shared
            exit(SelfTest.benchOCR() ? 0 : 4)
        }

        if let index = arguments.firstIndex(of: "--translate"), arguments.count > index + 1 {
            _ = NSApplication.shared
            let text = arguments[index + 1]
            Task {
                let ok = await SelfTest.translate(text)
                exit(ok ? 0 : 3)
            }
            return true
        }

        return false
    }
}

enum Diagnostics {
    static func run() async {
        print("=== GameLens 诊断 ===")
        print("1) 预检权限 CGPreflightScreenCaptureAccess: \(CGPreflightScreenCaptureAccess())")

        guard let region = CaptureRegion.load() else {
            print("2) 识别区域: ❌ 没有保存的区域（从没框选成功）")
            return
        }
        print("2) 识别区域: \(region.description)  比例 \(region.scale)x")

        let capturer = ScreenCapturer()
        do {
            let started = Date()
            let image = try await capturer.capture(region)
            print("3) 抓屏: ✅ 成功 \(image.width)×\(image.height)  用时 \(Int(Date().timeIntervalSince(started) * 1000))ms")

            let result = try OCR.recognize(image)
            print("4) OCR: \(result.lines.count) 行 / 置信度 \(String(format: "%.2f", result.averageConfidence))")
            print("   文本: 「\(result.text.prefix(120))」")

            if !result.text.isEmpty {
                let engine = EngineFactory.shared.engine(for: Settings.shared)
                do {
                    let translated = try await engine.translate(result.text, source: "en", target: "zh-Hans", notes: false)
                    print("5) 翻译(\(engine.displayName)): ✅ \(translated.prefix(80))")
                } catch {
                    print("5) 翻译: ❌ \(error.localizedDescription)")
                }
            } else {
                print("5) 翻译: 跳过（OCR 没读到文字，说明框选的区域现在是空的/纯色）")
            }
        } catch {
            print("3) 抓屏: ❌ \(error.localizedDescription)")
        }
    }
}
