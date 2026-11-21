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

    @Test("單元 05 數字：5 課，單字不和前面重複")
    func unit05() throws {
        let lib = try ContentLibrary.loadBundled()
        let u5 = lib.units[4]
        #expect(u5.number == 5)
        #expect(u5.available)
        #expect(u5.lessons.map(\.id) == ["U05L01", "U05L02", "U05L03", "U05L04", "U05L05"])
        #expect(u5.lessons.flatMap(\.vocabulary).count >= 50)
        let earlier = Set(lib.units.prefix(4).flatMap(\.lessons).flatMap(\.vocabulary).map(\.korean))
        #expect(u5.lessons.flatMap(\.vocabulary).allSatisfy { !earlier.contains($0.korean) })
    }

    @Test("單元 06 助詞反射訓練：語音問答題思考時間較短")
    func unit06() throws {
        let lib = try ContentLibrary.loadBundled()
        let u6 = lib.units[5]
        #expect(u6.number == 6)
        #expect(u6.available)
        #expect(u6.stage == .basicPatterns)
        #expect(u6.lessons.map(\.id) == ["U06L01", "U06L02", "U06L03", "U06L04", "U06L05"])
        let qa = u6.lessons.flatMap(\.drills).filter { $0.type == .questionAnswer }
        #expect(qa.allSatisfy { $0.thinkSeconds <= 6 })
        #expect(qa.flatMap(\.items).allSatisfy { $0.cueIsAudio == true })
        let earlier = Set(lib.units.prefix(5).flatMap(\.lessons).flatMap(\.vocabulary).map(\.korean))
        #expect(u6.lessons.flatMap(\.vocabulary).allSatisfy { !earlier.contains($0.korean) })
        // (으)로：ㄹ 收音接 로
        let answers = u6.lessons.flatMap(\.drills).flatMap(\.items).flatMap(\.answers)
        #expect(answers.contains("지하철로 가요."))
        #expect(!answers.contains { $0.contains("지하철으로") })
    }

    @Test("單元 07 時態：現在、過去、未來、進行都有練習")
    func unit07() throws {
        let lib = try ContentLibrary.loadBundled()
        let u7 = lib.units[6]
        #expect(u7.number == 7)
        #expect(u7.available)
        #expect(u7.lessons.map(\.id) == ["U07L01", "U07L02", "U07L03", "U07L04", "U07L05"])
        let answers = Set(u7.lessons.flatMap(\.drills).flatMap(\.items).flatMap(\.answers))
        #expect(answers.contains("먹었어요."))          // 過去
        #expect(answers.contains("만들 거예요."))       // 未來（ㄹ 語幹）
        #expect(answers.contains("들을 거예요."))       // 未來（ㄷ 不規則）
        #expect(answers.contains("지금 청소하고 있어요.")) // 進行
        #expect(answers.contains("공부 안 해요."))      // 名詞＋하다 的短否定
        #expect(!answers.contains { $0.contains("안 공부해요") })
        let earlier = Set(lib.units.prefix(6).flatMap(\.lessons).flatMap(\.vocabulary).map(\.korean))
        #expect(u7.lessons.flatMap(\.vocabulary).allSatisfy { !earlier.contains($0.korean) })
    }

    @Test("單元 08 敬語：三種語體都有，自己的動作不加敬語")
    func unit08() throws {
        let lib = try ContentLibrary.loadBundled()
        let u8 = lib.units[7]
        #expect(u8.number == 8)
        #expect(u8.available)
        #expect(u8.lessons.map(\.id) == ["U08L01", "U08L02", "U08L03", "U08L04", "U08L05"])
        // 半語課的情境對話與文法使用 반말
        let banmal = u8.lessons[3]
        #expect(banmal.speaking.speechLevel == .casual)
        #expect(banmal.grammar.allSatisfy { $0.speechLevel == .casual })
        // 說「我」的句子不能加主體敬語（*저는 … 가세요）
        let answers = u8.lessons.flatMap(\.drills).flatMap(\.items).flatMap(\.answers)
            + u8.lessons.flatMap(\.speaking.offlineScript).flatMap(\.answers)
        for a in answers where a.hasPrefix("저는") || a.hasPrefix("제가") {
            #expect(!a.contains("세요") && !a.contains("셨어요"), "\(a)")
        }
        #expect(answers.contains("사세요."))       // ㄹ 脫落
        #expect(answers.contains("하셨어요."))
        let earlier = Set(lib.units.prefix(7).flatMap(\.lessons).flatMap(\.vocabulary).map(\.korean))
        #expect(u8.lessons.flatMap(\.vocabulary).allSatisfy { !earlier.contains($0.korean) })
    }

    @Test("單元 09 實戰情境：-아/어서 前不加過去式、含數字答案都有韓文寫法")
    func unit09() throws {
        let lib = try ContentLibrary.loadBundled()
        let u9 = lib.units[8]
        #expect(u9.number == 9)
        #expect(u9.available)
        #expect(u9.stage == .dailyConversation)
        #expect(u9.lessons.map(\.id) == ["U09L01", "U09L02", "U09L03", "U09L04", "U09L05"])
        let items = u9.lessons.flatMap(\.drills).flatMap(\.items) + u9.lessons.flatMap(\.speaking.offlineScript)
        let answers = items.flatMap(\.answers)
        #expect(answers.contains("길을 잃어서 늦었어요."))
        #expect(!answers.contains { $0.contains("었어서") || $0.contains("았어서") || $0.contains("했어서") })
        for item in items where item.answers.contains(where: { $0.contains(where: \.isNumber) }) {
            #expect(item.answers.contains { !$0.contains(where: \.isNumber) }, "\(item.cue) 缺少韓文寫法")
        }
        let earlier = Set(lib.units.prefix(8).flatMap(\.lessons).flatMap(\.vocabulary).map(\.korean))
        #expect(u9.lessons.flatMap(\.vocabulary).allSatisfy { !earlier.contains($0.korean) })
    }

    @Test("單元 10 朋友聊天：以半語為主，追星課用禮貌語體")
    func unit10() throws {
        let lib = try ContentLibrary.loadBundled()
        let u10 = lib.units[9]
        #expect(u10.number == 10)
        #expect(u10.available)
        #expect(u10.lessons.map(\.id) == ["U10L01", "U10L02", "U10L03", "U10L04", "U10L05"])
        let levels = u10.lessons.map(\.speaking.speechLevel)
        #expect(levels == [.casual, .casual, .casual, .polite, .casual])
        // 網路用語課有子音縮寫
        #expect(u10.lessons[2].vocabulary.contains { $0.korean == "ㅋㅋ" })
        let answers = u10.lessons.flatMap(\.drills).flatMap(\.items).flatMap(\.answers)
        #expect(answers.contains("콘서트에 가 본 적 있어요."))
        #expect(answers.contains("늦을 것 같아요."))
        let earlier = Set(lib.units.prefix(9).flatMap(\.lessons).flatMap(\.vocabulary).map(\.korean))
        #expect(u10.lessons.flatMap(\.vocabulary).allSatisfy { !earlier.contains($0.korean) })
    }

    @Test("單元 11 聽力：每課 6 題聽力，廣播課用正式語體，轉述句型正確")
    func unit11() throws {
        let lib = try ContentLibrary.loadBundled()
        let u11 = lib.units[10]
        #expect(u11.number == 11)
        #expect(u11.available)
        #expect(u11.stage == .naturalSpeedListening)
        #expect(u11.lessons.map(\.id) == ["U11L01", "U11L02", "U11L03", "U11L04", "U11L05"])
        #expect(u11.lessons.allSatisfy { $0.listening.count >= 6 })
        #expect(u11.lessons[2].grammar.allSatisfy { $0.speechLevel == .formal })
        let answers = u11.lessons.flatMap(\.drills).flatMap(\.items).flatMap(\.answers)
        #expect(answers.contains("민수 씨가 오늘 못 온다고 했어요."))   // 動詞 -(느)ㄴ다고
        #expect(answers.contains("민수 씨가 학생이라고 했어요."))       // 名詞 -(이)라고
        #expect(answers.contains("내일 춥대요."))                      // -대요 縮略
        let earlier = Set(lib.units.prefix(10).flatMap(\.lessons).flatMap(\.vocabulary).map(\.korean))
        #expect(u11.lessons.flatMap(\.vocabulary).allSatisfy { !earlier.contains($0.korean) })
    }

    @Test("單元 12 實戰：總測驗涵蓋多項能力，三種語體都有")
    func unit12() throws {
        let lib = try ContentLibrary.loadBundled()
        let u12 = lib.units[11]
        #expect(u12.number == 12)
        #expect(u12.available)
        #expect(u12.stage == .freeConversation)
        #expect(u12.lessons.map(\.id) == ["U12L01", "U12L02", "U12L03", "U12L04", "U12L05"])
        let finalTest = try #require(u12.lessons.last).postTest
        #expect(Set(finalTest.map(\.skill)).isSuperset(of: [.listening, .grammar, .reading, .vocabulary, .speaking]))
        let levels = Set(try #require(u12.lessons.last).grammar.flatMap(\.examples).compactMap(\.speechLevel))
        #expect(levels.isSuperset(of: [.formal, .casual]))
    }

    @Test("全部 12 單元開放：60 課，單字不重複")
    func wholeCourse() throws {
        let lib = try ContentLibrary.loadBundled()
        #expect(lib.units.allSatisfy(\.available))
        #expect(lib.allLessons.count == 60)
        let words = lib.allVocabulary.map(\.korean)
        #expect(words.count >= 600)
        #expect(Set(words).count == words.count, "有單字在不同單元重複出現")
        // 每個課程階段至少有一個單元
        let stages = Set(lib.units.map(\.stage))
        #expect(stages.count >= 7)
    }

    @Test("數字答案：韓文、阿拉伯數字、千分位、語音辨識結果都判為正確")
    func numberAnswersAcceptDigits() throws {
        let lib = try ContentLibrary.loadBundled()
        let drills = try #require(lib.lesson(id: "U05L03")).drills + (try #require(lib.lesson(id: "U05L01"))).drills
        let time = try #require(drills.first { $0.id == "D2301" }?.items.first { $0.cue == "4:30" })
        for typed in ["네 시 삼십 분", "4시 30분", "4시 반"] {
            let g = DrillGrader.grade(response: typed, answers: time.answers, responseSeconds: 2, timeLimit: 7)
            #expect(g.verdict.isAcceptable, "\(typed)")
        }
        let price = try #require(drills.first { $0.id == "D2101" }?.items.first { $0.cue == "3,000" })
        let typedComma = DrillGrader.grade(response: "3,000원이에요.", answers: price.answers, responseSeconds: 2, timeLimit: 7)
        #expect(typedComma.verdict.isAcceptable)
        // iOS 語音辨識常輸出阿拉伯數字、沒有空格
        let spoken = SpeechAnswerGrader.grade(transcripts: ["3000원이에요"], answers: price.answers, responseSeconds: 2, timeLimit: 7)
        #expect(spoken.verdict == .correct)
        // 每一題含數字提示的 Drill，都同時提供韓文與阿拉伯數字答案
        let unit5Items = lib.units[4].lessons.flatMap(\.drills).flatMap(\.items)
        for item in unit5Items where item.answers.contains(where: { $0.contains(where: \.isNumber) }) {
            #expect(item.answers.contains { !$0.contains(where: \.isNumber) }, "\(item.cue) 缺少韓文寫法")
        }
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
