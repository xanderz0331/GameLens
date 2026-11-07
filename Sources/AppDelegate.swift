import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.shared

    private var overlay: OverlayPanel!
    private var pipeline: Pipeline!
    private var hotKey: GlobalHotKey!
    private var menuBar: MenuBarController!
    private var settingsController: SettingsWindowController!
    private let picker = RegionPickerController()
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        terminateDuplicateInstances()

        overlay = OverlayPanel()
        pipeline = Pipeline(settings: settings, overlay: overlay)
        settingsController = SettingsWindowController(settings: settings)

        hotKey = GlobalHotKey()
        hotKey.onTrigger = { [weak self] in
            guard let self else { return }
            self.pipeline.toggleOverlay()
            self.menuBar.refreshIcon()
        }
        _ = hotKey.register(settings.hotKey)

        menuBar = MenuBarController(
            pipeline: pipeline,
            settings: settings,
            onPickRegion: { [weak self] in self?.beginRegionPick() },
            onShowSettings: { [weak self] in self?.settingsController.show() },
            onOpenLog: { HistoryStore.revealInFinder() },
            onOpenPermission: { [weak self] in self?.openScreenRecordingSettings() },
            onShowWelcome: { [weak self] in self?.showWelcome(firstLaunch: false) }
        )

        pipeline.onStateChange = { [weak self] in
            self?.menuBar?.refreshIcon()
        }

        pipeline.onNeedRegion = { [weak self] in
            self?.beginRegionPick()
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .gameLensSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                _ = self.hotKey.register(self.settings.hotKey)
                self.pipeline.refreshOverlayStyle()
            }
        }

        if CommandLine.arguments.contains("--demo-overlay") {
            runOverlayDemo()
            return
        }

        bootstrap()
    }

    /// 调试用：在屏幕中间显示一条假字幕，方便截图检查视觉效果。
    private func runOverlayDemo() {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        let visible = screen.visibleFrame
        let fake = CGRect(x: visible.midX - 320, y: visible.midY - 60, width: 640, height: 120)
        let region = CaptureRegion.make(screen: screen, globalRect: fake)
        pipeline.setRegion(region)
        pipeline.showOverlayForAWhile()
        overlay.update(source: "I never asked for this, but here we are.",
                       target: "我从没要求过这些，但事已至此。",
                       region: region,
                       settings: settings)

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - 启动流程

    private func bootstrap() {
        if CGPreflightScreenCaptureAccess() {
            permissionReady()
        } else {
            _ = CGRequestScreenCaptureAccess()
            promptForPermission()
        }
    }

    private func permissionReady() {
        if let region = CaptureRegion.load() {
            pipeline.setRegion(region)
            menuBar.refreshIcon()
        } else {
            showWelcome(firstLaunch: true)
        }
    }

    private func promptForPermission() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "GameLens 需要「屏幕录制」权限"
        alert.informativeText = """
        读取画面里的文字必须要有这个权限。

        1. 点「打开系统设置」，在 隐私与安全性 › 屏幕录制 里勾选 GameLens
        2. 回到这里点「已授权，重新检查」
        3. 如果仍然不生效，请退出并重新打开 GameLens
        """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "已授权，重新检查")
        alert.addButton(withTitle: "稍后")
        alert.window.level = .floating
        alert.window.makeKeyAndOrderFront(nil)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openScreenRecordingSettings()
        case .alertSecondButtonReturn:
            if CGPreflightScreenCaptureAccess() {
                permissionReady()
            } else {
                let note = NSAlert()
                note.messageText = "系统还没放行"
                note.informativeText = "请先在系统设置里勾选 GameLens，然后**退出并重新打开本 App**。\n\n菜单栏图标 → 退出 GameLens。"
                note.addButton(withTitle: "好")
                note.window.level = .floating
                note.runModal()
            }
        default:
            break
        }
    }

    /// 只允许跑一个实例：重复启动时把旧的关掉，避免两个悬浮窗互相打架。
    private func terminateDuplicateInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }

        for app in others { app.terminate() }
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        for app in others where !app.isTerminated {
            app.forceTerminate()
        }
    }

    // MARK: - 界面

    func showWelcome(firstLaunch: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = firstLaunch ? "欢迎使用 GameLens" : "GameLens 使用说明"
        alert.informativeText = """
        1. 让游戏以「窗口」或「无边框窗口」模式运行（独占全屏下系统悬浮窗会被盖住）。
        2. 点下面的按钮，拖动鼠标框选游戏里出现台词的那一块区域（只框台词框，不用框整个屏幕）。
        3. 之后新台词一出现，译文会自动浮在台词框下方。
        4. 随时按 \(settings.hotKey.label) 隐藏 / 显示译文 —— 先自己读英文，卡住了再瞄一眼。
        """
        alert.addButton(withTitle: "开始框选区域")
        alert.addButton(withTitle: "稍后")

        if alert.runModal() == .alertFirstButtonReturn {
            beginRegionPick()
        }
    }

    func beginRegionPick() {
        let previous = pipeline.region
        pipeline.stop()

        picker.begin { [weak self] region in
            guard let self else { return }
            if let region {
                region.save()
                self.pipeline.setRegion(region)
            } else if let previous {
                self.pipeline.setRegion(previous)
            }
            self.menuBar.refreshIcon()
            NSApp.activate(ignoringOtherApps: false)
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension Notification.Name {
    static let gameLensSettingsChanged = Notification.Name("GameLensSettingsChanged")
}
