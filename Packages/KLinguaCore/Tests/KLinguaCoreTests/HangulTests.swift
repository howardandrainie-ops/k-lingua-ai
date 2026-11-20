import Testing
@testable import KLinguaCore

@Suite("韓文字母")
struct HangulTests {
    @Test("拆解與組合互為反函數")
    func roundTrip() throws {
        for word in ["가", "물", "닭", "쀍", "힣", "의", "꽃"] {
            let ch = try #require(word.first)
            let s = try #require(Hangul.decompose(ch))
            #expect(Hangul.compose(s) == ch)
        }
    }

    @Test("拆解內容正確")
    func decompose() {
        #expect(Hangul.decompose("물") == .init(initial: "ㅁ", medial: "ㅜ", final: "ㄹ"))
        #expect(Hangul.decompose("커") == .init(initial: "ㅋ", medial: "ㅓ", final: nil))
        #expect(Hangul.decompose("A") == nil)
        #expect(Hangul.jamo("책") == ["ㅊ", "ㅐ", "ㄱ"])
    }

    @Test("收音判斷看最後一個韓文音節")
    func batchim() {
        #expect(Hangul.hasBatchim("커피") == false)
        #expect(Hangul.hasBatchim("물") == true)
        #expect(Hangul.hasBatchim("선생님") == true)
        #expect(Hangul.hasBatchim("물.") == true)
        #expect(Hangul.hasBatchim("abc") == nil)
    }

    @Test("助詞依收音選擇", arguments: [
        ("커피", Hangul.Particle.object, "커피를"),
        ("물", .object, "물을"),
        ("저", .topic, "저는"),
        ("책", .topic, "책은"),
        ("우유", .subject, "우유가"),
        ("책", .subject, "책이"),
        ("학생", .copula, "학생이에요"),
        ("가수", .copula, "가수예요"),
        ("서울", .direction, "서울로"),
        ("집", .direction, "집으로"),
        ("버스", .direction, "버스로"),
    ])
    func particles(word: String, particle: Hangul.Particle, expected: String) {
        #expect(Hangul.attach(particle, to: word) == expected)
    }
}
