import Testing
@testable import KLinguaCore

@Suite("內建教材")
struct ContentTests {
    @Test("所有教材可以載入")
    func loads() throws {
        let lib = try ContentLibrary.loadBundled()
        #expect(lib.units.count == 12)
        #expect(lib.units.map(\.number) == Array(1...12))
    }

    @Test("教材完整性檢查沒有任何問題")
    func valid() throws {
        let lib = try ContentLibrary.loadBundled()
        let issues = ContentValidator.validate(lib)
        #expect(issues.isEmpty, "\(issues.map(\.description).joined(separator: "\n"))")
    }

    @Test("單元 01 有 5 課完整教材")
    func unit01() throws {
        let lib = try ContentLibrary.loadBundled()
        let u1 = try #require(lib.units.first)
        #expect(u1.available)
        #expect(u1.lessons.count == 5)
        #expect(lib.allVocabulary.count >= 40)
    }

    @Test("單元 02 有 5 課完整教材，涵蓋各種音變")
    func unit02() throws {
        let lib = try ContentLibrary.loadBundled()
        let u2 = lib.units[1]
        #expect(u2.number == 2)
        #expect(u2.available)
        #expect(u2.lessons.map(\.id) == ["U02L01", "U02L02", "U02L03", "U02L04", "U02L05"])
        #expect(u2.lessons.flatMap(\.vocabulary).count >= 50)
        let titles = u2.lessons.flatMap(\.pronunciation).map(\.title).joined()
        for rule in ["雙收音", "脫落", "鼻音化", "緊音化", "激音化", "弱化", "口蓋音化", "流音化"] {
            #expect(titles.contains(rule), "缺少 \(rule)")
        }
        // 第 2 課使用正式語體
        #expect(u2.lessons[1].grammar.allSatisfy { $0.speechLevel == .formal })
        // 單字 ID 接續第 1 單元、不重複
        let all = lib.allVocabulary.map(\.id)
        #expect(Set(all).count == all.count)
    }

    @Test("單元 03 有 5 課生活單字，以 S 級為主")
    func unit03() throws {
        let lib = try ContentLibrary.loadBundled()
        let u3 = lib.units[2]
        #expect(u3.number == 3)
        #expect(u3.available)
        #expect(u3.stage == .coreVocabulary)
        #expect(u3.lessons.map(\.id) == ["U03L01", "U03L02", "U03L03", "U03L04", "U03L05"])
        let words = u3.lessons.flatMap(\.vocabulary)
        #expect(words.count >= 55)
        #expect(words.filter { $0.tier == .s }.count * 2 > words.count, "S 級應佔多數")
        // 不重複教前面單元已經教過的單字
        let earlier = Set(lib.units.prefix(2).flatMap(\.lessons).flatMap(\.vocabulary).map(\.korean))
        #expect(words.allSatisfy { !earlier.contains($0.korean) })
    }

    @Test("單元 04 自我介紹：5 課，兼顧正式與日常禮貌語體")
    func unit04() throws {
        let lib = try ContentLibrary.loadBundled()
        let u4 = lib.units[3]
        #expect(u4.number == 4)
        #expect(u4.available)
        #expect(u4.lessons.map(\.id) == ["U04L01", "U04L02", "U04L03", "U04L04", "U04L05"])
        #expect(u4.lessons.flatMap(\.vocabulary).count >= 50)
        // 最後一課的情境對話用正式語體，其他課用日常禮貌語體
        #expect(u4.lessons.last?.speaking.speechLevel == .formal)
        #expect(u4.lessons.dropLast().allSatisfy { $0.speaking.speechLevel == .polite })
        // 主題助詞 은/는 依收音選擇
        let answers = u4.lessons.flatMap(\.drills).flatMap(\.items).flatMap(\.answers)
        #expect(answers.contains("선생님은 한국 사람이에요."))
        #expect(answers.contains("언니는 회사원이에요."))
        let earlier = Set(lib.units.prefix(3).flatMap(\.lessons).flatMap(\.vocabulary).map(\.korean))
        #expect(u4.lessons.flatMap(\.vocabulary).allSatisfy { !earlier.contains($0.korean) })
    }

    @Test("못 해요／못해요 兩種寫法都接受")
    func spacingVariantsAccepted() throws {
        let lib = try ContentLibrary.loadBundled()
        let set = try #require(lib.lesson(id: "U02L04")?.drills.first { $0.id == "D0901" })
        for item in set.items {
            let joined = item.answers[0].replacingOccurrences(of: "못 해요", with: "못해요")
            let g = DrillGrader.grade(response: joined, answers: item.answers, responseSeconds: 2, timeLimit: 8)
            #expect(g.verdict == .correct, "\(joined)")
        }
    }

    @Test("診斷測驗涵蓋七項能力，約 10 分鐘")
    func diagnostic() throws {
        let lib = try ContentLibrary.loadBundled()
        let skills = Set(lib.diagnostic.sections.map(\.skill))
        #expect(skills == [.hangulRecognition, .phonemeDiscrimination, .vocabulary, .grammar, .listening, .reading, .speaking])
        #expect(lib.diagnostic.estimatedMinutes <= 10)
        let count = lib.diagnostic.sections.reduce(0) { $0 + $1.questions.count }
        #expect((25...40).contains(count))
    }

    @Test("驗證器能抓到助詞錯誤")
    func validatorCatchesParticles() {
        #expect(!ContentValidator.particleProblems(in: "저는 물를 마셔요.").isEmpty)
        #expect(!ContentValidator.particleProblems(in: "책예요.").isEmpty)
        #expect(!ContentValidator.particleProblems(in: "커피이에요.").isEmpty)
        #expect(!ContentValidator.particleProblems(in: "책가 아니에요.").isEmpty)
        #expect(ContentValidator.particleProblems(in: "저는 커피를 마셔요.").isEmpty)
        #expect(ContentValidator.particleProblems(in: "아니요, 버스가 아니에요.").isEmpty)
    }

    @Test("新單字挑選：S 級優先、不超過第一格上限")
    func selector() throws {
        let lib = try ContentLibrary.loadBundled()
        let picked = VocabularySelector.nextNewWords(library: lib, introducedIDs: [], currentLessonID: "U01L02", box1Count: 0, count: 5)
        #expect(picked.count == 5)
        #expect(picked.allSatisfy { $0.tier == .s })
        let lessonIDs = Set(lib.units[0].lessons.prefix(2).flatMap(\.vocabulary).map(\.id))
        #expect(picked.allSatisfy { lessonIDs.contains($0.id) })
        let none = VocabularySelector.nextNewWords(library: lib, introducedIDs: [], currentLessonID: "U01L02",
                                                   box1Count: VocabularySelector.maxBox1Backlog, count: 5)
        #expect(none.isEmpty)
    }
}
