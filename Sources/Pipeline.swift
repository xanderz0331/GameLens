import AppKit
import Foundation

/// 识别流水线：抓图 → OCR → 判断是不是新台词 → 翻译 → 更新悬浮窗
@MainActor
final class Pipeline {
    private let settings: Settings
    private let overlay: OverlayPanel
    private let capturer = ScreenCapturer()

    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var isOverlayHidden = false
    private(set) var lastError: String?
    private(set) var lastSource = ""
    private(set) var lastTranslation = ""

    var region: CaptureRegion?
    var onStateChange: (() -> Void)?
    /// 没框选区域时按快捷键 → 走框选流程
    var onNeedRegion: (() -> Void)?

    private var loop: Task<Void, Never>?
    private var translateSequence = 0
    private var committedNormalized = ""
    private var candidateText = ""
    private var candidateNormalized = ""
    private var candidateCount = 0
    private var autoHideTask: Task<Void, Never>?

    init(settings: Settings, overlay: OverlayPanel) {
        self.settings = settings
        self.overlay = overlay
    }

    // MARK: - 生命周期

    func start() {
        guard region != nil, loop == nil else { return }
        isRunning = true

        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let interval = max(0.15, self.settings.interval)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        onStateChange?()
    }

    func stop() {
        loop?.cancel()
        loop = nil
        isRunning = false
        onStateChange?()
    }

    func restart() {
        stop()
        start()
    }

    /// 暂停 = 真的停掉抓屏线程，不是空转。
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        loop?.cancel()
        loop = nil
        overlay.hide()
        onStateChange?()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        start()
        onStateChange?()
    }

    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    func setRegion(_ region: CaptureRegion?) {
        self.region = region
        committedNormalized = ""
        candidateNormalized = ""
        candidateText = ""
        candidateCount = 0
        if region == nil {
            stop()
            isPaused = false
            overlay.clear()
            overlay.hide()
        } else {
            isPaused = false
            start()
        }
    }

    // MARK: - 悬浮窗

    func toggleOverlay() {
        // 还没框选区域 → 直接进入框选，而不是静默无事
        guard region != nil else {
            onNeedRegion?()
            return
        }

        if isOverlayHidden {
            isOverlayHidden = false
            overlay.update(source: lastSource, target: displayText(), region: region, settings: settings)
            overlay.show()
            scheduleAutoHide()
        } else {
            isOverlayHidden = true
            autoHideTask?.cancel()
            overlay.hide()
        }
        onStateChange?()
    }

    /// 快捷键呼出时到底显示什么：有译文给译文，有错误给错误，都没有就给提示
    private func displayText() -> String {
        if !lastTranslation.isEmpty { return lastTranslation }
        if let lastError { return "⚠︎ " + lastError }
        if isPaused { return "⏸ 已暂停识别" }
        if !isRunning { return "⚠︎ 识别没有启动" }
        return "👀 正在等台词出现…"
    }

    func showOverlayForAWhile() {
        if isOverlayHidden {
            isOverlayHidden = false
            overlay.update(source: lastSource, target: lastTranslation, region: region, settings: settings)
            overlay.show()
            scheduleAutoHide()
            onStateChange?()
        }
    }

    func refreshOverlayStyle() {
        overlay.update(source: lastSource, target: lastTranslation, region: region, settings: settings)
        if isOverlayHidden { overlay.hide() } else { overlay.show(animated: false) }
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        let seconds = settings.autoHideSeconds
        guard seconds > 0 else { return }
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard !self.isOverlayHidden else { return }
            self.isOverlayHidden = true
            self.overlay.hide()
            self.onStateChange?()
        }
    }

    // MARK: - 主循环

    private var ocrLanguages: [String] {
        switch settings.sourceLanguage {
        case "en": return ["en-US"]
        case "ja": return ["ja-JP"]
        case "ko": return ["ko-KR"]
        case "zh-Hans", "zh-Hant": return ["zh-Hans", "zh-Hant"]
        case "fr": return ["fr-FR"]
        case "de": return ["de-DE"]
        case "es": return ["es-ES"]
        case "it": return ["it-IT"]
        case "pt": return ["pt-BR"]
        case "ru": return ["ru-RU"]
        default: return ["en-US"]
        }
    }

    private func tick() async {
        guard isRunning, !isPaused, let region else { return }

        do {
            let image = try await capturer.capture(region)
            let boxed = SendableImage(image: image)
            let languages = ocrLanguages
            let result = try await Task.detached(priority: .userInitiated) {
                try OCR.recognize(boxed.image, languages: languages)
            }.value

            if lastError != nil {
                lastError = nil
                onStateChange?()
            }
            handle(result.text)
        } catch {
            let message = error.localizedDescription
            NSLog("[GameLens] 抓屏失败：\(message)")
            if message != lastError {
                let firstFailure = lastError == nil
                lastError = message
                if firstFailure, !isOverlayHidden {
                    overlay.update(source: "", target: "⚠︎ " + message, region: region, settings: settings)
                    overlay.show(animated: false)
                }
                onStateChange?()
            }
        }
    }

    /// 只有"连续两次抓到同样的文本"才认为是稳定的一句台词，
    /// 这样能避开打字机效果、淡入动画、以及角色名闪烁带来的抖动。
    private func handle(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizeForCompare(text)
        guard normalized.count >= 2 else { return }

        if normalized == committedNormalized {
            candidateCount = 0
            return
        }

        if normalized == candidateNormalized {
            candidateCount += 1
        } else {
            candidateNormalized = normalized
            candidateText = text
            candidateCount = 1
        }

        guard candidateCount >= 2 else { return }
        committedNormalized = normalized
        candidateCount = 0
        translateAndShow(candidateText)
    }

    private func translateAndShow(_ text: String) {
        translateSequence += 1
        let sequence = translateSequence

        let engine = EngineFactory.shared.engine(for: settings)
        let source = settings.sourceLanguage
        let target = settings.targetLanguage
        let notes = settings.showNotes && engine.supportsNotes

        Task { [weak self] in
            guard let self else { return }
            do {
                let translated = try await engine.translate(text, source: source, target: target, notes: notes)
                guard sequence == self.translateSequence else { return }
                self.apply(text: text, translation: translated)
            } catch {
                guard sequence == self.translateSequence else { return }
                self.lastError = error.localizedDescription
                self.lastSource = text
                self.overlay.update(source: text,
                                    target: "⚠️ \(error.localizedDescription)",
                                    region: self.region,
                                    settings: self.settings)
                if !self.isOverlayHidden { self.overlay.show(animated: false) }
                self.onStateChange?()
            }
        }
    }

    private func apply(text: String, translation: String) {
        lastSource = text
        lastTranslation = translation
        overlay.update(source: text, target: translation, region: region, settings: settings)
        if !isOverlayHidden { overlay.show(animated: false) }
        if settings.saveHistory {
            HistoryStore.append(source: text, translation: translation)
        }
        onStateChange?()
    }
}
