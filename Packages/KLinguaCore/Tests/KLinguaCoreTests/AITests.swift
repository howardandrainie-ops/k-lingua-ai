import Foundation
import Testing
@testable import KLinguaCore

@Suite("AI 服務層（不連網）")
struct AITests {
    let sample = AIRequest(system: "SYS", messages: [AIChatMessage(role: .user, text: "안녕하세요")], maxTokens: 500, wantsJSON: true)

    private func body(_ r: URLRequest) throws -> [String: Any] {
        let data = try #require(r.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func claudeRequestShape() throws {
        let r = try ProviderAPI.makeRequest(provider: .claude, model: "claude-opus-5-5", apiKey: " sk-ant-test ", request: sample)
        #expect(r.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(r.httpMethod == "POST")
        #expect(r.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(r.value(forHTTPHeaderField: "Authorization") == nil)
        let b = try body(r)
        #expect(b["model"] as? String == "claude-opus-5-5")
        #expect(b["system"] as? String == "SYS")
        #expect(b["max_tokens"] as? Int == 500)
        #expect(b["temperature"] == nil)
        #expect((b["messages"] as? [[String: Any]])?.first?["role"] as? String == "user")
        #expect((b["output_config"] as? [String: Any])?["effort"] as? String == "low")
        #expect(b["fallbacks"] as? String == "default")
    }

    @Test func claudeOlderModelOmitsNewFields() throws {
        let r = try ProviderAPI.makeRequest(provider: .claude, model: "claude-haiku-4-5", apiKey: "k", request: sample)
        let b = try body(r)
        #expect(b["output_config"] == nil)
        #expect(b["fallbacks"] == nil)
        #expect(r.value(forHTTPHeaderField: "anthropic-beta") == nil)
    }

    @Test func openAIRequestShape() throws {
        let r = try ProviderAPI.makeRequest(provider: .openai, model: "gpt-5-mini", apiKey: "sk-x", request: sample)
        #expect(r.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer sk-x")
        let b = try body(r)
        let messages = try #require(b["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect((b["response_format"] as? [String: Any])?["type"] as? String == "json_object")
    }

    @Test func geminiRequestShape() throws {
        let r = try ProviderAPI.makeRequest(provider: .gemini, model: "gemini-2.5-flash", apiKey: "AIza", request: sample)
        #expect(r.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        #expect(r.value(forHTTPHeaderField: "x-goog-api-key") == "AIza")
        #expect(r.url?.query == nil) // 金鑰不放在網址
        let b = try body(r)
        let contents = try #require(b["contents"] as? [[String: Any]])
        #expect(contents.first?["role"] as? String == "user")
        #expect((b["generationConfig"] as? [String: Any])?["responseMimeType"] as? String == "application/json")
    }

    @Test func missingKeyAndBadModelAreRejected() {
        #expect(throws: AIServiceError.missingKey) {
            try ProviderAPI.makeRequest(provider: .claude, model: "claude-opus-5-5", apiKey: "  ", request: sample)
        }
        #expect(throws: AIServiceError.invalidModel) {
            try ProviderAPI.makeRequest(provider: .gemini, model: "a/b?c", apiKey: "k", request: sample)
        }
    }

    @Test func parseClaudeText() throws {
        let json = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"안녕하세요"}],"stop_reason":"end_turn"}"#
        #expect(try ProviderAPI.parseResponse(provider: .claude, status: 200, data: Data(json.utf8)) == "안녕하세요")
    }

    @Test func parseClaudeRefusal() {
        let json = #"{"content":[],"stop_reason":"refusal","stop_details":{"type":"refusal","explanation":"x"}}"#
        #expect(throws: AIServiceError.refused("x")) {
            try ProviderAPI.parseResponse(provider: .claude, status: 200, data: Data(json.utf8))
        }
    }

    @Test func parseOpenAIAndGemini() throws {
        let o = #"{"choices":[{"message":{"role":"assistant","content":"네"}}]}"#
        #expect(try ProviderAPI.parseResponse(provider: .openai, status: 200, data: Data(o.utf8)) == "네")
        let g = #"{"candidates":[{"content":{"parts":[{"text":"생각","thought":true},{"text":"좋아요"}]}}]}"#
        #expect(try ProviderAPI.parseResponse(provider: .gemini, status: 200, data: Data(g.utf8)) == "좋아요")
    }

    @Test func httpErrorsCarryStatusAndMessage() {
        let e = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        do {
            _ = try ProviderAPI.parseResponse(provider: .claude, status: 401, data: Data(e.utf8))
            Issue.record("應該拋出錯誤")
        } catch let error as AIServiceError {
            #expect(error == .http(status: 401, message: "invalid x-api-key"))
            #expect(error.userMessage.contains("API Key 無效"))
        } catch {
            Issue.record("錯誤型別不對")
        }
    }

    @Test func emptyResponseIsAnError() {
        #expect(throws: AIServiceError.emptyResponse) {
            try ProviderAPI.parseResponse(provider: .openai, status: 200, data: Data(#"{"choices":[{"message":{"content":"  "}}]}"#.utf8))
        }
    }

    @Test func coachReplyParsesJSONInsideText() {
        let text = """
        好的：
        {"reply":"네, 아이스 아메리카노 하나요?","translation":"好的，一杯冰美式嗎？","correction":{"original":"아이스 아메리카노 하나 주세요요","corrected":"아이스 아메리카노 하나 주세요.","explanation":"多了一個요"},"note":null}
        """
        let r = CoachReplyParser.parse(text)
        #expect(r.structured)
        #expect(r.reply == "네, 아이스 아메리카노 하나요?")
        #expect(r.correction?.corrected == "아이스 아메리카노 하나 주세요.")
        #expect(r.note == nil)
    }

    @Test func coachIgnoresSpacingOnlyCorrections() {
        let text = #"{"reply":"네","translation":"好","correction":{"original":"여기서먹을게요","corrected":"여기서 먹을게요.","explanation":"空格"},"note":""}"#
        let r = CoachReplyParser.parse(text)
        #expect(r.correction == nil)
        #expect(r.note == nil)
    }

    @Test func coachFallsBackToPlainText() {
        let r = CoachReplyParser.parse("어서 오세요!")
        #expect(!r.structured)
        #expect(r.reply == "어서 오세요!")
    }

    @Test func historyStartsWithUserAndIncludesOpening() {
        let h = CoachPrompt.history(opening: "어서 오세요.", turns: [("커피 주세요.", "네.")], latestUser: "얼마예요?")
        #expect(h.count == 3)
        #expect(h.first?.role == .user)
        #expect(h.first?.text.contains("어서 오세요.") == true)
        #expect(h.last == AIChatMessage(role: .user, text: "얼마예요?"))
        let single = CoachPrompt.history(opening: "안녕!", turns: [], latestUser: "안녕")
        #expect(single.count == 1)
        #expect(single[0].text.contains("안녕!"))
    }

    @Test func fifteenScenariosCoverAllSpeechLevels() {
        let all = ScenarioCatalog.all
        #expect(all.count == 15)
        #expect(Set(all.map(\.id)).count == 15)
        for level in SpeechLevel.allCases {
            #expect(all.contains { $0.speechLevel == level })
        }
        // 正式語體場景的開場白要用 합쇼체；半語場景不能有 -요 結尾
        for s in all where s.speechLevel == .formal {
            #expect(s.opening.contains("니다") || s.opening.contains("니까"))
        }
        for s in all where s.speechLevel == .casual {
            #expect(!s.opening.contains("요?") && !s.opening.contains("요."))
        }
        let prompt = CoachPrompt.system(scenario: all[0], learnerLevel: "初級", knownWords: ["커피", "주세요"])
        #expect(prompt.contains("해요체"))
        #expect(prompt.contains("커피"))
    }
}
