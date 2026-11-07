import Foundation
import AppKit
import Combine

enum EngineKind: String, CaseIterable, Identifiable {
    case auto, apple, google, deepl, openai

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:   return "自动（优先系统离线）"
        case .apple:  return "Apple 离线翻译"
        case .google: return "Google 网页翻译"
        case .deepl:  return "DeepL"
        case .openai: return "自定义 API（OpenAI 兼容）"
        }
    }

    var shortLabel: String {
        switch self {
        case .auto:   return "自动"
        case .apple:  return "Apple 离线"
        case .google: return "Google"
        case .deepl:  return "DeepL"
        case .openai: return "自定义 API"
        }
    }
}

struct LangOption: Identifiable, Hashable {
    let id: String
    let name: String
}

struct HotKeyPreset: Hashable, Identifiable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let label: String
    var id: String { "\(keyCode)-\(carbonModifiers)" }

    static let all: [HotKeyPreset] = [
        HotKeyPreset(keyCode: 17, carbonModifiers: 2048, label: "⌥ T"),
        HotKeyPreset(keyCode: 17, carbonModifiers: 6144, label: "⌃ ⌥ T"),
        HotKeyPreset(keyCode: 2,  carbonModifiers: 2048, label: "⌥ D"),
        HotKeyPreset(keyCode: 49, carbonModifiers: 2048, label: "⌥ Space"),
        HotKeyPreset(keyCode: 3,  carbonModifiers: 6144, label: "⌃ ⌥ F"),
        HotKeyPreset(keyCode: 120, carbonModifiers: 0,   label: "F2")
    ]

    static var defaultValue: HotKeyPreset { all[0] }

    /// 退出快捷键，固定 ⌃⌥Q（kVK_ANSI_Q = 12，control 4096 + option 2048）
    static let quit = HotKeyPreset(keyCode: 12, carbonModifiers: 6144, label: "⌃ ⌥ Q")

    static func match(keyCode: UInt32, modifiers: UInt32) -> HotKeyPreset? {
        all.first { $0.keyCode == keyCode && $0.carbonModifiers == modifiers }
    }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    static let languages: [LangOption] = [
        LangOption(id: "en", name: "英语"),
        LangOption(id: "ja", name: "日语"),
        LangOption(id: "ko", name: "韩语"),
        LangOption(id: "zh-Hans", name: "简体中文"),
        LangOption(id: "zh-Hant", name: "繁体中文"),
        LangOption(id: "fr", name: "法语"),
        LangOption(id: "de", name: "德语"),
        LangOption(id: "es", name: "西班牙语"),
        LangOption(id: "it", name: "意大利语"),
        LangOption(id: "pt", name: "葡萄牙语"),
        LangOption(id: "ru", name: "俄语")
    ]

    private let store = UserDefaults.standard

    @Published var engine: EngineKind { didSet { store.set(engine.rawValue, forKey: "engine") } }
    @Published var sourceLanguage: String { didSet { store.set(sourceLanguage, forKey: "sourceLanguage") } }
    @Published var targetLanguage: String { didSet { store.set(targetLanguage, forKey: "targetLanguage") } }

    @Published var interval: Double { didSet { store.set(interval, forKey: "interval"); notifyStyleChange() } }
    @Published var fontSize: Double { didSet { store.set(fontSize, forKey: "fontSize"); notifyStyleChange() } }
    @Published var backgroundOpacity: Double { didSet { store.set(backgroundOpacity, forKey: "backgroundOpacity"); notifyStyleChange() } }
    @Published var showSource: Bool { didSet { store.set(showSource, forKey: "showSource"); notifyStyleChange() } }
    @Published var showNotes: Bool { didSet { store.set(showNotes, forKey: "showNotes") } }
    @Published var saveHistory: Bool { didSet { store.set(saveHistory, forKey: "saveHistory") } }
    @Published var autoHideSeconds: Double { didSet { store.set(autoHideSeconds, forKey: "autoHideSeconds") } }

    @Published var deeplKey: String { didSet { store.set(deeplKey, forKey: "deeplKey") } }
    @Published var openAIBase: String { didSet { store.set(openAIBase, forKey: "openAIBase") } }
    @Published var openAIKey: String { didSet { store.set(openAIKey, forKey: "openAIKey") } }
    @Published var openAIModel: String { didSet { store.set(openAIModel, forKey: "openAIModel") } }

    @Published var hotKeyKeyCode: UInt32 { didSet { store.set(Int(hotKeyKeyCode), forKey: "hotKeyKeyCode"); notifyStyleChange() } }
    @Published var hotKeyModifiers: UInt32 { didSet { store.set(Int(hotKeyModifiers), forKey: "hotKeyModifiers"); notifyStyleChange() } }

    var hotKey: HotKeyPreset {
        get { HotKeyPreset.match(keyCode: hotKeyKeyCode, modifiers: hotKeyModifiers) ?? .defaultValue }
        set { hotKeyKeyCode = newValue.keyCode; hotKeyModifiers = newValue.carbonModifiers }
    }

    private init() {
        engine = EngineKind(rawValue: store.string(forKey: "engine") ?? "auto") ?? .auto
        sourceLanguage = store.string(forKey: "sourceLanguage") ?? "en"
        targetLanguage = store.string(forKey: "targetLanguage") ?? "zh-Hans"

        interval = (store.object(forKey: "interval") as? Double) ?? 0.4
        fontSize = (store.object(forKey: "fontSize") as? Double) ?? 30
        backgroundOpacity = (store.object(forKey: "backgroundOpacity") as? Double) ?? 0.66
        showSource = (store.object(forKey: "showSource") as? Bool) ?? true
        showNotes = (store.object(forKey: "showNotes") as? Bool) ?? true
        saveHistory = (store.object(forKey: "saveHistory") as? Bool) ?? true
        autoHideSeconds = (store.object(forKey: "autoHideSeconds") as? Double) ?? 0

        deeplKey = store.string(forKey: "deeplKey") ?? ""
        openAIBase = store.string(forKey: "openAIBase") ?? "https://api.deepseek.com/v1"
        openAIKey = store.string(forKey: "openAIKey") ?? ""
        openAIModel = store.string(forKey: "openAIModel") ?? "deepseek-chat"

        hotKeyKeyCode = UInt32((store.object(forKey: "hotKeyKeyCode") as? Int) ?? Int(HotKeyPreset.defaultValue.keyCode))
        hotKeyModifiers = UInt32((store.object(forKey: "hotKeyModifiers") as? Int) ?? Int(HotKeyPreset.defaultValue.carbonModifiers))
    }

    private func notifyStyleChange() {
        NotificationCenter.default.post(name: .gameLensSettingsChanged, object: nil)
    }

    func languageName(_ id: String) -> String {
        Settings.languages.first { $0.id == id }?.name ?? id
    }
}
