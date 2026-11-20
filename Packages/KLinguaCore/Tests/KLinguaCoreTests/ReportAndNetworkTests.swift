import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import KLinguaCore

@Suite("週報")
struct WeeklyReportTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func weekStartsOnMonday() {
        // 2026-11-20 是星期五
        let start = WeeklyReportBuilder.weekStart(for: date(2026, 11, 20), calendar: calendar)
        #expect(calendar.component(.weekday, from: start) == 2)
        #expect(start == calendar.startOfDay(for: date(2026, 11, 16)))
    }

    @Test func emptyWeekSaysSo() {
        let r = WeeklyReportBuilder.build(weekStart: date(2026, 11, 16, 0), attempts: [], days: [], mistakes: [], calendar: calendar)
        #expect(r.attempts == 0)
        #expect(r.accuracy == nil)
        #expect(r.skills.allSatisfy { $0.accuracy == nil })
        #expect(r.suggestions.first?.contains("還沒有作答紀錄") == true)
    }

    @Test func computesFromRealSamplesOnly() {
        let start = date(2026, 11, 16, 0)
        var attempts: [AttemptSample] = []
        // 本週單字 8 題對 6 題；文法 3 題（不足 5 題，不評分）
        for i in 0..<8 { attempts.append(.init(skill: .vocabulary, correct: i < 6, at: date(2026, 11, 17))) }
        for _ in 0..<3 { attempts.append(.init(skill: .grammar, correct: true, at: date(2026, 11, 18))) }
        // 上週單字 5 題全對 → 本週下降 25 個百分點
        for _ in 0..<5 { attempts.append(.init(skill: .vocabulary, correct: true, at: date(2026, 11, 10))) }
        // 下週的資料不應計入
        attempts.append(.init(skill: .listening, correct: true, at: date(2026, 11, 24)))

        let days = [StudyDaySample(day: date(2026, 11, 17, 0), seconds: 1800, newWords: 8, reviews: 20),
                    StudyDaySample(day: date(2026, 11, 18, 0), seconds: 600, newWords: 0, reviews: 10)]
        let mistakes = [MistakeSample(category: "particleError", at: date(2026, 11, 17)),
                        MistakeSample(category: "particleError", at: date(2026, 11, 18)),
                        MistakeSample(category: "particleError", at: date(2026, 11, 19)),
                        MistakeSample(category: "incorrect", at: date(2026, 11, 19))]
        let r = WeeklyReportBuilder.build(weekStart: start, attempts: attempts, days: days, mistakes: mistakes, calendar: calendar)

        #expect(r.attempts == 11)
        #expect(r.studyMinutes == 40)
        #expect(r.activeDays == 2)
        #expect(r.newWords == 8)
        #expect(r.reviews == 30)
        let vocab = r.skills.first { $0.skill == .vocabulary }!
        #expect(vocab.accuracy == 0.75)
        #expect(vocab.previousAccuracy == 1.0)
        #expect(r.skills.first { $0.skill == .grammar }!.accuracy == nil)
        #expect(r.skills.first { $0.skill == .listening }!.attempts == 0)
        #expect(r.topMistakes.first == .init(category: "particleError", count: 3))
        #expect(r.suggestions.contains { $0.contains("下降 25") })
        #expect(r.suggestions.contains { $0.contains("文法") && $0.contains("暫不評分") })
        #expect(r.suggestions.contains { $0.contains("只練習了 2 天") })
    }

    @Test func reportRoundTripsThroughJSON() throws {
        let r = WeeklyReportBuilder.build(weekStart: date(2026, 11, 16, 0),
                                          attempts: (0..<6).map { _ in .init(skill: .reading, correct: true, at: date(2026, 11, 17)) },
                                          days: [], mistakes: [], calendar: calendar)
        let data = try JSONEncoder().encode(r)
        #expect(try JSONDecoder().decode(WeeklyReportData.self, from: data) == r)
    }
}

/// 攔截 HTTP 請求，不連網測試完整的「建立請求 → 傳送 → 解析」流程
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let (status, data) = Self.responder?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@Suite("AI 用戶端（攔截網路）", .serialized)
struct HTTPAIClientTests {
    @Test func claudeRoundTrip() async throws {
        StubURLProtocol.responder = { _ in
            (200, Data(#"{"content":[{"type":"text","text":"{\"reply\":\"네, 알겠습니다.\",\"translation\":\"好的\",\"correction\":null,\"note\":null}"}],"stop_reason":"end_turn"}"#.utf8))
        }
        let client = HTTPAIClient(provider: .claude, model: "claude-opus-5-5", apiKey: "test-key", session: StubURLProtocol.session())
        let text = try await client.complete(AIRequest(system: "s", messages: [.init(role: .user, text: "커피 주세요")]))
        let reply = CoachReplyParser.parse(text)
        #expect(reply.structured)
        #expect(reply.reply == "네, 알겠습니다.")
        #expect(StubURLProtocol.lastRequest?.value(forHTTPHeaderField: "x-api-key") == "test-key")
    }

    @Test func unauthorizedMapsToReadableError() async {
        StubURLProtocol.responder = { _ in
            (401, Data(#"{"error":{"message":"Incorrect API key provided"}}"#.utf8))
        }
        let client = HTTPAIClient(provider: .openai, model: "gpt-5-mini", apiKey: "bad", session: StubURLProtocol.session())
        do {
            _ = try await client.complete(AIRequest(system: "s", messages: [.init(role: .user, text: "hi")]))
            Issue.record("應該失敗")
        } catch let e as AIServiceError {
            #expect(e == .http(status: 401, message: "Incorrect API key provided"))
        } catch {
            Issue.record("錯誤型別不對：\(error)")
        }
    }
}
