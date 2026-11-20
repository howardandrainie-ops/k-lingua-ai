import Foundation
import Testing
@testable import KLinguaCore

@Suite("語音比對與說話偵測")
struct SpeechTests {
    @Test func exactMatchIgnoresSpacesAndPunctuation() {
        let c = SpeechComparison.check(target: "저는 커피를 마셔요.", transcripts: ["저는커피를 마셔요"])
        #expect(c.verdict == .recognizedAsTarget)
        #expect(c.matchRatio == 1)
        #expect(c.differences.isEmpty)
    }

    @Test func picksClosestAlternative() {
        let c = SpeechComparison.check(target: "우유예요", transcripts: ["오늘", "우유에요"])
        #expect(c.heard == "우유에요")
        #expect(c.verdict == .closeMatch)
        #expect(c.differences.count == 1)
    }

    @Test func aspirationHint() throws {
        let c = SpeechComparison.check(target: "불", transcripts: ["풀"])
        let d = try #require(c.differences.first)
        #expect(d.kind == .substituted)
        #expect(d.hint?.contains("平音") == true)
        // 單音節要提醒辨識不穩定
        #expect(!c.notes.isEmpty)
    }

    @Test func finalConsonantHint() throws {
        let c = SpeechComparison.check(target: "밤", transcripts: ["밥"])
        let hint = try #require(c.differences.first?.hint)
        #expect(hint.contains("收音"))
    }

    @Test func mergedVowelsAreNotBlamedOnUser() throws {
        let c = SpeechComparison.check(target: "개", transcripts: ["게"])
        let hint = try #require(c.differences.first?.hint)
        #expect(hint.contains("幾乎同音"))
    }

    @Test func missingSyllableIsReported() {
        let c = SpeechComparison.check(target: "아버지", transcripts: ["아지"])
        #expect(c.differences.contains { $0.kind == .missing && $0.expected == "버" })
    }

    @Test func nothingRecognized() {
        let c = SpeechComparison.check(target: "우유", transcripts: ["", "  "])
        #expect(c.verdict == .nothingRecognized)
        #expect(c.matchRatio == 0)
    }

    @Test func speechGraderIgnoresSpacing() {
        let g = SpeechAnswerGrader.grade(transcripts: ["커피하나 주세요"], answers: ["커피 하나 주세요."], responseSeconds: 2, timeLimit: 5)
        #expect(g.verdict == .correct)
        #expect(g.withinTimeLimit)
    }

    @Test func speechGraderUsesBestCandidate() {
        let g = SpeechAnswerGrader.grade(transcripts: ["커피 마셔요", "커피를 마셔요"], answers: ["커피를 마셔요."], responseSeconds: 6, timeLimit: 5)
        #expect(g.verdict.isAcceptable)
        #expect(!g.withinTimeLimit)
    }

    @Test func speechGraderDetectsParticleError() {
        let g = SpeechAnswerGrader.grade(transcripts: ["물를 마셔요"], answers: ["물을 마셔요."], responseSeconds: 2, timeLimit: 5)
        #expect(g.verdict == .particleError)
        #expect(g.feedback.contains("辨識結果"))
    }

    @Test func speechGraderEmpty() {
        let g = SpeechAnswerGrader.grade(transcripts: [], answers: ["네"], responseSeconds: 2, timeLimit: 5)
        #expect(g.verdict == .incorrect)
    }

    @Test func voiceOnsetAndEnd() {
        var v = VoiceActivityDetector()
        let frame = 0.02
        var t = 0.0
        // 安靜環境 -60 dB，0.5 秒後開始說話，持續 1 秒，之後安靜
        while t < 3.0 {
            let level: Float = (t >= 0.5 && t < 1.5) ? -20 : -60
            v.feed(levelDB: level, at: t)
            t += frame
        }
        let onset = v.onset
        #expect(onset != nil)
        #expect(abs((onset ?? 0) - 0.5) < 0.05)
        let end = v.endOfSpeech ?? 0
        #expect(end >= 1.5 + v.silenceToEnd - 0.05)
    }

    @Test func shortNoiseIsNotOnset() {
        var v = VoiceActivityDetector()
        for i in 0..<100 {
            let t = Double(i) * 0.02
            // 單一音框的雜音（例如碰到手機）
            v.feed(levelDB: i == 30 ? -10 : -60, at: t)
        }
        #expect(v.onset == nil)
    }

    @Test func rms() {
        #expect(VoiceActivityDetector.rmsDB([Float]()) == -160)
        #expect(VoiceActivityDetector.rmsDB([Float](repeating: 0, count: 10)) == -160)
        #expect(abs(VoiceActivityDetector.rmsDB([Float](repeating: 1, count: 10))) < 0.001)
    }
}
