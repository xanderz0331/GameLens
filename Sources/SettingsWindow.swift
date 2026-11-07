import AppKit

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 纯 AppKit 写的设置窗口（不依赖 SwiftUI 宏插件）。
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: Settings

    private var enginePopup: NSPopUpButton!
    private var sourcePopup: NSPopUpButton!
    private var targetPopup: NSPopUpButton!
    private var notesCheckbox: NSButton!
    private var deeplField: NSSecureTextField!
    private var baseField: NSTextField!
    private var keyField: NSSecureTextField!
    private var modelField: NSTextField!
    private var testButton: NSButton!
    private var testLabel: NSTextField!

    private var fontSlider: NSSlider!
    private var fontValueLabel: NSTextField!
    private var opacitySlider: NSSlider!
    private var opacityValueLabel: NSTextField!
    private var showSourceCheckbox: NSButton!

    private var intervalSlider: NSSlider!
    private var intervalValueLabel: NSTextField!
    private var hotkeyPopup: NSPopUpButton!
    private var autoHideSlider: NSSlider!
    private var autoHideValueLabel: NSTextField!
    private var historyCheckbox: NSButton!

    init(settings: Settings) {
        self.settings = settings
        super.init()
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        refreshFromSettings()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshFromSettings() {
        guard window != nil else { return }
        enginePopup.selectItem(at: EngineKind.allCases.firstIndex(of: settings.engine) ?? 0)
        sourcePopup.selectItem(at: Settings.languages.firstIndex(where: { $0.id == settings.sourceLanguage }) ?? 0)
        targetPopup.selectItem(at: Settings.languages.firstIndex(where: { $0.id == settings.targetLanguage }) ?? 0)
        notesCheckbox.state = settings.showNotes ? .on : .off

        deeplField.stringValue = settings.deeplKey
        baseField.stringValue = settings.openAIBase
        keyField.stringValue = settings.openAIKey
        modelField.stringValue = settings.openAIModel

        fontSlider.doubleValue = settings.fontSize
        fontValueLabel.stringValue = "\(Int(settings.fontSize))"
        opacitySlider.doubleValue = settings.backgroundOpacity
        opacityValueLabel.stringValue = "\(Int(settings.backgroundOpacity * 100))%"
        showSourceCheckbox.state = settings.showSource ? .on : .off

        intervalSlider.doubleValue = settings.interval
        intervalValueLabel.stringValue = String(format: "%.2f 秒", settings.interval)
        hotkeyPopup.selectItem(at: HotKeyPreset.all.firstIndex(of: settings.hotKey) ?? 0)
        autoHideSlider.doubleValue = settings.autoHideSeconds
        autoHideValueLabel.stringValue = settings.autoHideSeconds == 0 ? "关闭" : "\(Int(settings.autoHideSeconds)) 秒"
        historyCheckbox.state = settings.saveHistory ? .on : .off
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshFromSettings()
    }

    // MARK: - 构建界面

    private func buildWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "GameLens 设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = makeContent()
        window.center()
        self.window = window
    }

    private func makeContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let kinds = EngineKind.allCases
        enginePopup = makePopup(kinds.map { $0.label }, action: #selector(engineChanged))
        sourcePopup = makePopup(Settings.languages.map { $0.name }, action: #selector(sourceChanged))
        targetPopup = makePopup(Settings.languages.map { $0.name }, action: #selector(targetChanged))

        notesCheckbox = makeCheckbox("AI 讲解生词 / 俚语（仅自定义 API 生效）", action: #selector(notesChanged))

        deeplField = makeSecureField("DeepL API Key")
        baseField = makeField("Base URL")
        keyField = makeSecureField("API Key")
        modelField = makeField("模型名")

        testButton = NSButton(title: "翻译一句试试", target: self, action: #selector(runTest))
        testButton.bezelStyle = .rounded

        testLabel = NSTextField(wrappingLabelWithString: "")
        testLabel.font = .systemFont(ofSize: 12)
        testLabel.textColor = .secondaryLabelColor
        testLabel.isSelectable = true
        testLabel.preferredMaxLayoutWidth = 440

        fontSlider = makeSlider(16, 56, 1, #selector(fontChanged))
        fontValueLabel = makeValueLabel(40)
        opacitySlider = makeSlider(0, 1, 0.02, #selector(opacityChanged))
        opacityValueLabel = makeValueLabel(48)
        showSourceCheckbox = makeCheckbox("同时显示英文原文", action: #selector(showSourceChanged))

        intervalSlider = makeSlider(0.2, 1.5, 0.05, #selector(intervalChanged))
        intervalValueLabel = makeValueLabel(64)
        hotkeyPopup = makePopup(HotKeyPreset.all.map { $0.label }, action: #selector(hotkeyChanged))
        autoHideSlider = makeSlider(0, 20, 1, #selector(autoHideChanged))
        autoHideValueLabel = makeValueLabel(56)
        historyCheckbox = makeCheckbox("把台词存成 Markdown 复习笔记", action: #selector(historyChanged))

        stack.addArrangedSubview(sectionTitle("翻译引擎"))
        stack.addArrangedSubview(row("引擎", enginePopup))
        stack.addArrangedSubview(row("原文语言", sourcePopup))
        stack.addArrangedSubview(row("译文语言", targetPopup))
        stack.addArrangedSubview(notesCheckbox)

        stack.addArrangedSubview(sectionTitle("自定义 API（OpenAI 兼容：DeepSeek / Kimi / Ollama …）"))
        stack.addArrangedSubview(row("Base URL", baseField))
        stack.addArrangedSubview(row("API Key", keyField))
        stack.addArrangedSubview(row("模型名", modelField))

        stack.addArrangedSubview(sectionTitle("DeepL（可选）"))
        stack.addArrangedSubview(row("API Key", deeplField))

        let testRow = NSStackView(views: [testButton, testLabel])
        testRow.orientation = .horizontal
        testRow.spacing = 12
        testRow.alignment = .top
        stack.addArrangedSubview(sectionTitle("测试"))
        stack.addArrangedSubview(testRow)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("字幕外观"))
        stack.addArrangedSubview(row("字号", sliderRow(fontSlider, fontValueLabel)))
        stack.addArrangedSubview(row("背景不透明度", sliderRow(opacitySlider, opacityValueLabel)))
        stack.addArrangedSubview(showSourceCheckbox)

        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(sectionTitle("识别与快捷键"))
        stack.addArrangedSubview(row("刷新间隔", sliderRow(intervalSlider, intervalValueLabel)))
        stack.addArrangedSubview(row("显示 / 隐藏", hotkeyPopup))
        stack.addArrangedSubview(row("自动隐藏", sliderRow(autoHideSlider, autoHideValueLabel)))
        stack.addArrangedSubview(historyCheckbox)

        let hint = NSTextField(wrappingLabelWithString: "推荐刷新间隔 0.3 ~ 0.6 秒。「自动隐藏」开启后，每次按快捷键显示译文，到时间会自动藏起来，方便先自己读英文。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.preferredMaxLayoutWidth = 440
        stack.addArrangedSubview(hint)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        return scroll
    }

    // MARK: - 控件工厂

    private func makePopup(_ titles: [String], action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: titles)
        popup.target = self
        popup.action = action
        popup.translatesAutoresizingMaskIntoConstraints = false
        return popup
    }

    private func makeCheckbox(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func makeField(_ placeholder: String) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        return field
    }

    private func makeSecureField(_ placeholder: String) -> NSSecureTextField {
        let field = NSSecureTextField(string: "")
        field.placeholderString = placeholder
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true
        return field
    }

    private func makeSlider(_ min: Double, _ max: Double, _ step: Double, _ action: Selector) -> NSSlider {
        let slider = NSSlider(value: min, minValue: min, maxValue: max, target: self, action: action)
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        return slider
    }

    private func makeValueLabel(_ width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    private func sliderRow(_ slider: NSSlider, _ valueLabel: NSTextField) -> NSView {
        let stack = NSStackView(views: [slider, valueLabel])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        return stack
    }

    private func sectionTitle(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        return box
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 96).isActive = true

        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.alignment = .centerY
        return stack
    }

    // MARK: - 动作

    @objc private func engineChanged() {
        settings.engine = EngineKind.allCases[max(0, enginePopup.indexOfSelectedItem)]
        EngineFactory.shared.resetAutoFallback()
    }

    @objc private func sourceChanged() {
        settings.sourceLanguage = Settings.languages[max(0, sourcePopup.indexOfSelectedItem)].id
    }

    @objc private func targetChanged() {
        settings.targetLanguage = Settings.languages[max(0, targetPopup.indexOfSelectedItem)].id
    }

    @objc private func notesChanged() {
        settings.showNotes = notesCheckbox.state == .on
    }

    @objc private func fontChanged() {
        settings.fontSize = fontSlider.doubleValue
        fontValueLabel.stringValue = "\(Int(fontSlider.doubleValue))"
    }

    @objc private func opacityChanged() {
        settings.backgroundOpacity = opacitySlider.doubleValue
        opacityValueLabel.stringValue = "\(Int(opacitySlider.doubleValue * 100))%"
    }

    @objc private func showSourceChanged() {
        settings.showSource = showSourceCheckbox.state == .on
    }

    @objc private func intervalChanged() {
        settings.interval = intervalSlider.doubleValue
        intervalValueLabel.stringValue = String(format: "%.2f 秒", intervalSlider.doubleValue)
    }

    @objc private func hotkeyChanged() {
        let index = max(0, hotkeyPopup.indexOfSelectedItem)
        settings.hotKey = HotKeyPreset.all[index]
    }

    @objc private func autoHideChanged() {
        settings.autoHideSeconds = autoHideSlider.doubleValue
        autoHideValueLabel.stringValue = autoHideSlider.doubleValue == 0 ? "关闭" : "\(Int(autoHideSlider.doubleValue)) 秒"
    }

    @objc private func historyChanged() {
        settings.saveHistory = historyCheckbox.state == .on
    }

    @objc private func runTest() {
        testButton.isEnabled = false
        testLabel.stringValue = "正在测试…"
        testLabel.textColor = .secondaryLabelColor

        settings.deeplKey = deeplField.stringValue
        settings.openAIBase = baseField.stringValue
        settings.openAIKey = keyField.stringValue
        settings.openAIModel = modelField.stringValue

        let engine = EngineFactory.shared.engine(for: settings)
        let source = settings.sourceLanguage
        let target = settings.targetLanguage
        let notes = settings.showNotes && engine.supportsNotes

        Task {
            do {
                let output = try await engine.translate("I never asked for this, but here we are.",
                                                        source: source,
                                                        target: target,
                                                        notes: notes)
                testLabel.stringValue = "✅ " + output
                testLabel.textColor = .labelColor
            } catch {
                testLabel.stringValue = "❌ " + error.localizedDescription
                testLabel.textColor = .systemRed
            }
            testButton.isEnabled = true
        }
    }
}
