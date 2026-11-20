import Foundation
import Testing
@testable import KLinguaCore

@Suite("練習組題與評分")
struct PracticeBuilderTests {
    let library = try! ContentLibrary.loadBundled()

    @Test func seededGeneratorIsReproducible() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        #expect((0..<5).map { _ in a.next() } == (0..<5).map { _ in b.next() })
        #expect(SeededGenerator.seed("U01L01") == SeededGenerator.seed("U01L01"))
        #expect(SeededGenerator.seed("U01L01") != SeededGenerator.seed("U01L02"))
    }

    @Test func typedAnswersIgnorePunctuation() {
        let q = QuizQuestion(id: "t", skill: .speaking, kind: .speaking, prompt: "說出：這是什麼？",
                             acceptedAnswers: ["이거 뭐예요?"], explanation: "")
        #expect(QuizScoring.isCorrect(q, response: .text("이거 뭐예요")))
        #expect(!QuizScoring.isCorrect(q, response: .text("이거 뭐에요")))
        #expect(!QuizScoring.isCorrect(q, response: .text("  ")))
        #expect(!QuizScoring.isCorrect(q, response: .dontKnow))
    }

    @Test func choiceScoring() {
        let q = QuizQuestion(id: "c", skill: .vocabulary, kind: .choice, prompt: "", options: ["a", "b"], answerIndex: 1, explanation: "")
        #expect(QuizScoring.isCorrect(q, response: .choice(1)))
        #expect(!QuizScoring.isCorrect(q, response: .choice(0)))
        #expect(q.correctAnswerText == "b")
    }

    @Test func diagnosticSectionScoresCountUnansweredAsWrong() {
        let test = library.diagnostic
        let firstSection = test.sections[0]
        let ids = Set(firstSection.questions.prefix(2).map(\.id))
        let scores = QuizScoring.sectionScores(test, correctIDs: ids)
        #expect(scores.count == test.sections.count)
        #expect(scores[0].correct == 2)
        #expect(scores[0].total == firstSection.questions.count)
        #expect(scores.dropFirst().allSatisfy { $0.correct == 0 })
        // 完全零基礎 → 從第 1 單元開始
        #expect(PlacementEngine.place(QuizScoring.sectionScores(test, correctIDs: [])).startUnitNumber == 1)
    }

    @Test func distractorsAreDistinctAndIncludeTarget() throws {
        let words = try #require(library.units.first?.lessons.first?.vocabulary)
        var rng = SeededGenerator(seed: 7)
        for word in words {
            let opts = DistractorPicker.options(for: word, pool: library.allVocabulary, label: \.chinese, using: &rng)
            #expect(opts.count == 4)
            #expect(opts.contains { $0.id == word.id })
            #expect(Set(opts.map(\.chinese)).count == 4)
        }
    }

    @Test func meaningQuizAnswersPointAtTheWord() throws {
        let lesson = try #require(library.units.first?.lessons.first)
        let quiz = DistractorPicker.meaningQuiz(for: lesson.vocabulary, pool: library.allVocabulary, seed: 1)
        #expect(quiz.count == lesson.vocabulary.count)
        for (q, word) in zip(quiz, lesson.vocabulary) {
            #expect(q.correctAnswerText == word.chinese)
        }
    }

    @Test func recallClassifierDetectsSimilarWords() {
        #expect(RecallClassifier.errorForWrongChoice(targetKorean: "달", chosenKorean: "딸") == .confusedWithSimilar)
        #expect(RecallClassifier.errorForWrongChoice(targetKorean: "우유", chosenKorean: "커피") == .forgotten)
    }

    @Test func discriminationQuestionsAreValid() {
        let points = library.allLessons.flatMap(\.pronunciation)
        let pairs = DiscriminationBuilder.minimalPairs(points, count: 12, seed: 3)
        #expect(pairs.count == 12)
        for q in pairs { #expect(q.options[q.answerIndex] == q.audio) }
        let sounds = DiscriminationBuilder.sounds(points, count: 12, seed: 3)
        #expect(sounds.count == 12)
        for q in sounds {
            #expect(q.options[q.answerIndex] == q.audio)
            #expect(Set(q.options).count == q.options.count)
        }
        #expect(DiscriminationBuilder.minimalPairs([], count: 5, seed: 1).isEmpty)
    }

    @Test func dailyCheckCoversSeveralSkills() {
        let lessons = Array(library.allLessons.prefix(2))
        let qs = DailyCheckBuilder.questions(from: lessons, count: 6, seed: 9)
        #expect(qs.count == 6)
        #expect(Set(qs.map(\.id)).count == 6)
        #expect(Set(qs.map(\.skill)).count >= 4)
    }

    @Test func listeningItemsConvertToQuestions() throws {
        let item = try #require(library.allLessons.first?.listening.first)
        let q = item.asQuizQuestion
        #expect(q.kind == .listeningChoice)
        #expect(q.skill == .listening)
        #expect(QuizScoring.isCorrect(q, response: .choice(item.answerIndex)))
    }
}
