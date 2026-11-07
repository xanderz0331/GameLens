import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = Settings.shared

    private var overlay: OverlayPanel!
    private var pipeline: Pipeline!
    private var hotKey: GlobalHotKey!
    private var quitHotKey: GlobalHotKey!
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

        hotKey = GlobalHotKey(id: 1)
        hotKey.onTrigger = { [weak self] in
            guard let self else { return }
            self.pipeline.toggleOverlay()
            self.menuBar.refreshIcon()
        }
        _ = hotKey.register(settings.hotKey)

        // ⌃⌥Q 随时退出，不用去找菜单栏图标
        quitHotKey = GlobalHotKey(id: 2)
        quitHotKey.onTrigger = { NSApp.terminate(nil) }
        _ = quitHotKey.register(HotKeyPreset.quit)

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

    /// 不再用 CGPreflightScreenCaptureAccess 把关（它在部分系统上会误报 false，
    /// 导致明明有权限也永远启动不了）。这里只主动请求一次，然后无条件先把流水线跑起来；
    /// 真的抓不到画面时，错误会显示在悬浮窗里。
    private func bootstrap() {
        if !CGPreflightScreenCaptureAccess(),
           !UserDefaults.standard.bool(forKey: "askedScreenRecording") {
            UserDefaults.standard.set(true, forKey: "askedScreenRecording")
            _ = CGRequestScreenCaptureAccess()
        }
        permissionReady()
    }

    private func permissionReady() {
        if let region = CaptureRegion.load() {
            pipeline.setRegion(region)
            menuBar.refreshIcon()
        } else {
            showWelcome(firstLaunch: true)
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
