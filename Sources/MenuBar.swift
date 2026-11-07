import AppKit

private final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings: Settings
    private let pipeline: Pipeline
    private var actions: [MenuAction] = []

    private let onPickRegion: () -> Void
    private let onShowSettings: () -> Void
    private let onOpenLog: () -> Void
    private let onOpenPermission: () -> Void
    private let onShowWelcome: () -> Void

    init(pipeline: Pipeline,
         settings: Settings,
         onPickRegion: @escaping () -> Void,
         onShowSettings: @escaping () -> Void,
         onOpenLog: @escaping () -> Void,
         onOpenPermission: @escaping () -> Void,
         onShowWelcome: @escaping () -> Void) {
        self.pipeline = pipeline
        self.settings = settings
        self.onPickRegion = onPickRegion
        self.onShowSettings = onShowSettings
        self.onOpenLog = onOpenLog
        self.onOpenPermission = onOpenPermission
        self.onShowWelcome = onShowWelcome
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "GameLens")
            button.image?.isTemplate = true
            button.toolTip = "GameLens · 游戏台词翻译"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func refreshIcon() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if pipeline.region == nil {
            symbol = "character.bubble"
        } else if pipeline.isPaused {
            symbol = "pause.circle"
        } else if pipeline.lastError != nil {
            symbol = "exclamationmark.bubble"
        } else if pipeline.isOverlayHidden {
            symbol = "eye.slash"
        } else {
            symbol = "character.bubble.fill"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "GameLens")
        image?.isTemplate = true
        button.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        actions.removeAll()

        let status = NSMenuItem(title: statusTitle(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if let error = pipeline.lastError {
            let item = NSMenuItem(title: "⚠︎ " + String(error.prefix(70)), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        add(menu, title: pipeline.region == nil ? "框选识别区域…" : "重新框选识别区域…") { [unowned self] in self.onPickRegion() }

        let overlayTitle = pipeline.isOverlayHidden
            ? "显示翻译字幕　(\(settings.hotKey.label))"
            : "隐藏翻译字幕　(\(settings.hotKey.label))"
        add(menu, title: overlayTitle) { [unowned self] in self.pipeline.toggleOverlay() }

        add(menu, title: pipeline.isPaused ? "继续识别（恢复抓屏）" : "暂停识别（停止抓屏）") { [unowned self] in
            self.pipeline.togglePause()
            self.refreshIcon()
        }

        menu.addItem(.separator())

        let engineItem = NSMenuItem(title: "翻译引擎：\(settings.engine.shortLabel)", action: nil, keyEquivalent: "")
        let engineMenu = NSMenu()
        for kind in EngineKind.allCases {
            let action = MenuAction { [unowned self] in
                self.settings.engine = kind
                EngineFactory.shared.resetAutoFallback()
            }
            actions.append(action)
            let item = NSMenuItem(title: kind.label, action: #selector(MenuAction.run), keyEquivalent: "")
            item.target = action
            item.state = settings.engine == kind ? .on : .off
            engineMenu.addItem(item)
        }
        engineItem.submenu = engineMenu
        menu.addItem(engineItem)

        add(menu, title: "设置…") { [unowned self] in self.onShowSettings() }

        menu.addItem(.separator())

        add(menu, title: "打开对话记录") { [unowned self] in self.onOpenLog() }
        add(menu, title: "屏幕录制权限…") { [unowned self] in self.onOpenPermission() }
        add(menu, title: "使用说明") { [unowned self] in self.onShowWelcome() }

        menu.addItem(.separator())

        add(menu, title: "退出 GameLens（彻底关闭）　⌃⌥Q") {
            NSApp.terminate(nil)
        }
    }

    private func statusTitle() -> String {
        guard let region = pipeline.region else { return "尚未框选识别区域" }
        let languagePair = "\(settings.languageName(settings.sourceLanguage)) → \(settings.languageName(settings.targetLanguage))"
        return "\(region.description) · \(settings.engine.shortLabel) · \(languagePair)"
    }

    private func add(_ menu: NSMenu, title: String, _ handler: @escaping () -> Void) {
        let action = MenuAction(handler)
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        item.target = action
        menu.addItem(item)
    }
}
