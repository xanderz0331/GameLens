import Foundation
#if canImport(Translation)
import Translation
#endif

enum TranslationFailure: LocalizedError {
    case notConfigured(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let text): return text
        case .message(let text): return text
        }
    }
}

protocol TranslationEngine {
    var displayName: String { get }
    var supportsNotes: Bool { get }
    func translate(_ text: String, source: String, target: String, notes: Bool) async throws -> String
}


// MARK: - 网络层：系统代理坏了就自动切直连

/// 很多 Mac 上开着系统代理但代理本身是死的（Clash 挂了、节点失效），
/// URLSession 会困在代理里报 -1200。这里先走系统代理，失败立刻改走直连并记住。
enum NetClient {
    private static var mode: Int? = nil   // nil = 未探测, 0 = 系统代理, 1 = 直连
    private static let lock = NSLock()

    private static let systemSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    private static let directSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]   // 空字典 = 不用代理
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        let known = mode
        lock.unlock()

        if known == 1 { return try await directSession.data(for: request) }
        if known == 0 { return try await systemSession.data(for: request) }

        do {
            let result = try await systemSession.data(for: request)
            lock.lock(); mode = 0; lock.unlock()
            return result
        } catch {
            let result = try await directSession.data(for: request)
            lock.lock(); mode = 1; lock.unlock()
            NSLog("[GameLens] 系统代理不可用，已切换到直连")
            return result
        }
    }

    static func reset() {
        lock.lock(); mode = nil; lock.unlock()
    }
}

// MARK: - 语言代码

enum LangCode {
    static func google(_ id: String) -> String {
        switch id {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        default: return id
        }
    }

    static func deepl(_ id: String) -> String {
        switch id {
        case "zh-Hans": return "ZH-HANS"
        case "zh-Hant": return "ZH-HANT"
        default: return id.uppercased()
        }
    }
}

// MARK: - Apple 系统离线翻译

struct AppleOfflineEngine: TranslationEngine {
    var displayName: String { "Apple 离线" }
    var supportsNotes: Bool { false }

    func translate(_ text: String, source: String, target: String, notes: Bool) async throws -> String {
        #if canImport(Translation)
        guard #available(macOS 26.0, *) else {
            throw TranslationFailure.notConfigured("Apple 离线翻译需要 macOS 26 或更新版本。")
        }
        let sourceLanguage = Locale.Language(identifier: source)
        let targetLanguage = Locale.Language(identifier: target)

        let availability = LanguageAvailability()
        switch await availability.status(from: sourceLanguage, to: targetLanguage) {
        case .installed:
            break
        case .supported:
            throw TranslationFailure.notConfigured(
                "系统还没下载「\(source) → \(target)」离线语言包。打开 Mac 自带的「翻译」App 翻译一句话即可安装，或把引擎切成 Google / 自定义 API。"
            )
        default:
            throw TranslationFailure.notConfigured("系统不支持这个语言对。")
        }

        let session = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        let response = try await session.translate(text)
        return response.targetText
        #else
        throw TranslationFailure.notConfigured("当前系统没有 Translation 框架。")
        #endif
    }
}

// MARK: - Google 网页翻译（免密钥）

struct GoogleEngine: TranslationEngine {
    var displayName: String { "Google" }
    var supportsNotes: Bool { false }

    func translate(_ text: String, source: String, target: String, notes: Bool) async throws -> String {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: LangCode.google(source)),
            URLQueryItem(name: "tl", value: LangCode.google(target)),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text)
        ]
        guard let url = components.url else {
            throw TranslationFailure.message("请求地址不合法。")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                         forHTTPHeaderField: "User-Agent")

        let (data, response) = try await NetClient.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TranslationFailure.message("Google 返回 HTTP \(http.statusCode)，可能被网络环境拦截。")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else {
            throw TranslationFailure.message("Google 返回了无法解析的内容。")
        }
        let translated = segments.compactMap { segment -> String? in
            guard let array = segment as? [Any], let piece = array.first as? String else { return nil }
            return piece
        }.joined()

        guard !translated.isEmpty else {
            throw TranslationFailure.message("Google 没有返回译文。")
        }
        return translated
    }
}


// MARK: - MyMemory（免密钥，国内通常可直连）

struct MyMemoryEngine: TranslationEngine {
    var displayName: String { "MyMemory" }
    var supportsNotes: Bool { false }

    func translate(_ text: String, source: String, target: String, notes: Bool) async throws -> String {
        let pair = "\(LangCode.google(source))|\(LangCode.google(target))"
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
        let pairEncoded = pair.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? pair
        guard let url = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=\(pairEncoded)") else {
            throw TranslationFailure.message("MyMemory 地址不合法")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await NetClient.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw TranslationFailure.message("MyMemory 不可用")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["responseData"] as? [String: Any],
              let translated = payload["translatedText"] as? String else {
            throw TranslationFailure.message("MyMemory 返回内容无法解析")
        }
        let cleaned = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw TranslationFailure.message("MyMemory 返回空译文")
        }
        if cleaned.contains("MYMEMORY WARNING") {
            throw TranslationFailure.message("MyMemory 今日免费额度已用完")
        }
        return cleaned
    }
}

// MARK: - DeepL

struct DeepLEngine: TranslationEngine {
    let apiKey: String
    var displayName: String { "DeepL" }
    var supportsNotes: Bool { false }

    func translate(_ text: String, source: String, target: String, notes: Bool) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw TranslationFailure.notConfigured("还没有填 DeepL API Key，可以在设置里填写。")
        }
        let host = key.hasSuffix(":fx") ? "https://api-free.deepl.com/v2/translate"
                                         : "https://api.deepl.com/v2/translate"
        guard let url = URL(string: host) else {
            throw TranslationFailure.message("DeepL 地址不合法。")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("DeepL-Auth-Key \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = "text=\(urlEncode(text))&target_lang=\(LangCode.deepl(target))"
        if source != target { body += "&source_lang=\(LangCode.deepl(source))" }
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await NetClient.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationFailure.message("DeepL 没有响应。")
        }
        guard http.statusCode == 200 else {
            throw TranslationFailure.message("DeepL 返回 HTTP \(http.statusCode)：\(String(data: data, encoding: .utf8)?.prefix(160) ?? "")")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = json["translations"] as? [[String: Any]],
              let first = translations.first?["text"] as? String else {
            throw TranslationFailure.message("DeepL 返回内容无法解析。")
        }
        return first
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - OpenAI 兼容接口（DeepSeek / Kimi / OpenRouter / Ollama / OpenAI ...）

struct OpenAIEngine: TranslationEngine {
    let baseURL: String
    let apiKey: String
    let model: String
    var displayName: String { "自定义 API" }
    var supportsNotes: Bool { true }

    private var prompt: String {
        """
        你是嵌在游戏悬浮字幕里的翻译引擎。用户发来的是一句英文游戏角色对话。
        请翻译成自然、口语化的简体中文，长度尽量短，适合直接当字幕显示。
        """
    }

    private var noteInstruction: String {
        """

        如果原文里有值得学习的俚语、短语动词、习语或语法点，请在译文后另起一行，
        以「▸ 」开头，用不超过 22 个字的中文简要说明。没有就只输出译文。
        """
    }

    func translate(_ text: String, source: String, target: String, notes: Bool) async throws -> String {
        guard let url = Self.chatCompletionsURL(baseURL) else {
            throw TranslationFailure.notConfigured("自定义 API 的 Base URL 没填或格式不对。")
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelName.isEmpty else {
            throw TranslationFailure.notConfigured("自定义 API 的模型名没填。")
        }

        let systemContent = prompt + (notes ? noteInstruction : "")
        let payload: [String: Any] = [
            "model": modelName,
            "temperature": 0.2,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemContent],
                ["role": "user", "content": text]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await NetClient.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationFailure.message("自定义 API 没有响应。")
        }
        guard http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw TranslationFailure.message("接口返回 HTTP \(http.statusCode)：\(snippet)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationFailure.message("接口返回内容无法解析。")
        }
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw TranslationFailure.message("接口返回了空译文。")
        }
        return cleaned
    }

    static func chatCompletionsURL(_ base: String) -> URL? {
        var value = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix("/chat/completions") { return URL(string: value) }
        if value.hasSuffix("/v1") { return URL(string: value + "/chat/completions") }
        if value.contains("/v1/") { return URL(string: value + "/chat/completions") }
        return URL(string: value + "/v1/chat/completions")
    }
}

// MARK: - 自动模式

final class AutoEngine: TranslationEngine {
    var displayName: String { "自动" }
    var supportsNotes: Bool { false }

    private var preferred: TranslationEngine?

    private var candidates: [TranslationEngine] {
        // 顺序：离线优先（零延迟、不依赖网络）→ 国内可直连 → 最后才试 Google
        [AppleOfflineEngine(), MyMemoryEngine(), GoogleEngine()]
    }

    func translate(_ text: String, source: String, target: String, notes: Bool) async throws -> String {
        // 上次成功的通道优先复用，避免每次都从 Apple 开始试探
        if let preferred {
            if let result = try? await preferred.translate(text, source: source, target: target, notes: notes) {
                return result
            }
            self.preferred = nil
        }

        var lastError: Error = TranslationFailure.message("没有可用的翻译通道")
        for engine in candidates {
            for attempt in 0..<2 {
                do {
                    let result = try await engine.translate(text, source: source, target: target, notes: notes)
                    preferred = engine
                    NSLog("[GameLens] 翻译通道：\(engine.displayName)")
                    return result
                } catch {
                    lastError = error
                    FileHandle.standardError.write("[通道失败] \(engine.displayName) #\(attempt + 1): \(error.localizedDescription)\n".data(using: .utf8)!)
                    if attempt == 0 { try? await Task.sleep(nanoseconds: 300_000_000) }
                }
            }
        }
        throw lastError
    }

    func resetFallback() { preferred = nil }
}

// MARK: - 工厂

final class EngineFactory {
    static let shared = EngineFactory()

    private let autoEngine = AutoEngine()
    private var cachedSignature = ""
    private var cachedEngine: TranslationEngine = GoogleEngine()

    func engine(for settings: Settings) -> TranslationEngine {
        let signature = [
            settings.engine.rawValue,
            settings.deeplKey,
            settings.openAIBase,
            settings.openAIKey,
            settings.openAIModel
        ].joined(separator: "|")

        if signature == cachedSignature { return cachedEngine }
        cachedSignature = signature

        switch settings.engine {
        case .auto:   cachedEngine = autoEngine
        case .apple:  cachedEngine = AppleOfflineEngine()
        case .google: cachedEngine = GoogleEngine()
        case .deepl:  cachedEngine = DeepLEngine(apiKey: settings.deeplKey)
        case .openai: cachedEngine = OpenAIEngine(baseURL: settings.openAIBase,
                                                  apiKey: settings.openAIKey,
                                                  model: settings.openAIModel)
        }
        return cachedEngine
    }

    func resetAutoFallback() {
        autoEngine.resetFallback()
    }
}
