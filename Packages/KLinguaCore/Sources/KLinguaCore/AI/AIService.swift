import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// 可替換的 AI 服務層。App 只依賴 `AIClient`，不知道背後是哪一家。
// API Key 由 App 從 Keychain 讀出後傳入，這個套件不儲存任何金鑰。

public enum AIProvider: String, Codable, Sendable, CaseIterable, Identifiable {
    case claude
    case openai
    case gemini

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .claude: "Claude（Anthropic）"
        case .openai: "OpenAI"
        case .gemini: "Gemini（Google）"
        }
    }

    /// 預設模型。各家模型名稱會更新，使用者可在設定頁修改，並用「測試連線」確認。
    public var defaultModel: String {
        switch self {
        case .claude: "claude-opus-5-5"
        case .openai: "gpt-5-mini"
        case .gemini: "gemini-2.5-flash"
        }
    }

    public var keyPlaceholder: String {
        switch self {
        case .claude: "sk-ant-…"
        case .openai: "sk-…"
        case .gemini: "AIza…"
        }
    }

    public var consoleURL: URL {
        switch self {
        case .claude: URL(string: "https://platform.claude.com/settings/keys")!
        case .openai: URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        }
    }
}

public struct AIChatMessage: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct AIRequest: Sendable, Equatable {
    public var system: String
    public var messages: [AIChatMessage]
    public var maxTokens: Int
    /// 要求回傳 JSON（OpenAI / Gemini 有對應的 JSON 模式；Claude 由系統提示要求）
    public var wantsJSON: Bool

    public init(system: String, messages: [AIChatMessage], maxTokens: Int = 4000, wantsJSON: Bool = false) {
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
        self.wantsJSON = wantsJSON
    }
}

public enum AIServiceError: Error, Equatable, Sendable {
    case missingKey
    case invalidModel
    case http(status: Int, message: String)
    case refused(String?)
    case emptyResponse
    case decoding(String)
    case network(String)

    /// 給使用者看的說明（繁體中文）
    public var userMessage: String {
        switch self {
        case .missingKey:
            return "尚未設定 API Key。"
        case .invalidModel:
            return "模型名稱不正確。"
        case .http(let status, let message):
            let reason: String
            switch status {
            case 400: reason = "請求格式或模型名稱有誤"
            case 401, 403: reason = "API Key 無效或沒有權限"
            case 404: reason = "找不到這個模型，請確認模型名稱"
            case 429: reason = "請求太頻繁或帳戶額度不足"
            case 500...599: reason = "AI 服務暫時無法使用，請稍後再試"
            default: reason = "AI 服務回傳錯誤"
            }
            return "\(reason)（HTTP \(status)）\(message.isEmpty ? "" : "：\(message)")"
        case .refused(let detail):
            return "AI 服務拒絕回答這段內容。\(detail ?? "")"
        case .emptyResponse:
            return "AI 沒有回傳內容。"
        case .decoding(let m):
            return "無法讀取 AI 回應：\(m)"
        case .network(let m):
            return "網路連線失敗：\(m)"
        }
    }
}

public protocol AIClient: Sendable {
    func complete(_ request: AIRequest) async throws -> String
}

/// 各家 API 的請求格式與回應解析（不連網，可單元測試）
public enum ProviderAPI {
    /// Anthropic Messages API 版本
    public static let anthropicVersion = "2026-10-21"

    /// 支援 effort 設定與伺服器端備援（refusal fallback）的 Claude 模型
    static let claudeModelsWithEffort: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"]
    static let claudeModelsWithFallback: Set<String> = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-2"]

    public static func makeRequest(provider: AIProvider, model: String, apiKey: String, request: AIRequest) throws -> URLRequest {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIServiceError.missingKey }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, model.allSatisfy({ $0.isLetter || $0.isNumber || "-._:".contains($0) }) else {
            throw AIServiceError.invalidModel
        }

        let url: URL
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: [String: Any]

        switch provider {
        case .claude:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            headers["x-api-key"] = key
            headers["anthropic-version"] = anthropicVersion
            body = [
                "model": model,
                "max_tokens": request.maxTokens,
                "system": request.system,
                "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
            ]
            if claudeModelsWithEffort.contains(model) {
                // 對話練習不需要深度推理：低 effort 回應較快、花費較少
                body["output_config"] = ["effort": "low"]
            }
            if claudeModelsWithFallback.contains(model) {
                // 安全分類器誤拒時，由伺服器自動改用備援模型
                headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
                body["fallbacks"] = "default"
            }

        case .openai:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            headers["Authorization"] = "Bearer \(key)"
            body = [
                "model": model,
                "max_completion_tokens": request.maxTokens,
                "messages": [["role": "system", "content": request.system]]
                    + request.messages.map { ["role": $0.role.rawValue, "content": $0.text] },
            ]
            if request.wantsJSON { body["response_format"] = ["type": "json_object"] }

        case .gemini:
            guard let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let u = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encoded):generateContent") else {
                throw AIServiceError.invalidModel
            }
            url = u
            headers["x-goog-api-key"] = key
            var generation: [String: Any] = ["maxOutputTokens": request.maxTokens]
            if request.wantsJSON { generation["responseMimeType"] = "application/json" }
            body = [
                "systemInstruction": ["parts": [["text": request.system]]],
                "contents": request.messages.map {
                    ["role": $0.role == .user ? "user" : "model", "parts": [["text": $0.text]]] as [String: Any]
                },
                "generationConfig": generation,
            ]
        }

        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 90
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return r
    }

    public static func parseResponse(provider: AIProvider, status: Int, data: Data) throws -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            let message = ((json?["error"] as? [String: Any])?["message"] as? String) ?? ""
            throw AIServiceError.http(status: status, message: String(message.prefix(200)))
        }
        guard let json else { throw AIServiceError.decoding("不是 JSON") }

        let text: String
        switch provider {
        case .claude:
            if json["stop_reason"] as? String == "refusal" {
                let details = json["stop_details"] as? [String: Any]
                throw AIServiceError.refused(details?["explanation"] as? String)
            }
            let blocks = json["content"] as? [[String: Any]] ?? []
            text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        case .openai:
            let choices = json["choices"] as? [[String: Any]] ?? []
            let message = choices.first?["message"] as? [String: Any]
            if let refusal = message?["refusal"] as? String, !refusal.isEmpty { throw AIServiceError.refused(refusal) }
            text = message?["content"] as? String ?? ""
        case .gemini:
            let candidates = json["candidates"] as? [[String: Any]] ?? []
            if candidates.first?["finishReason"] as? String == "SAFETY" { throw AIServiceError.refused(nil) }
            let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            // 思考型模型會回傳 thought 部分，只取一般文字
            text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIServiceError.emptyResponse }
        return trimmed
    }
}

/// 透過 HTTPS 呼叫各家 API
public struct HTTPAIClient: AIClient {
    public let provider: AIProvider
    public let model: String
    private let apiKey: String
    private let session: URLSession

    public init(provider: AIProvider, model: String, apiKey: String, session: URLSession = .shared) {
        self.provider = provider
        self.model = model
        self.apiKey = apiKey
        self.session = session
    }

    public func complete(_ request: AIRequest) async throws -> String {
        let urlRequest = try ProviderAPI.makeRequest(provider: provider, model: model, apiKey: apiKey, request: request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AIServiceError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try ProviderAPI.parseResponse(provider: provider, status: status, data: data)
    }
}
