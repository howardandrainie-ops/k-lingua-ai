import SwiftUI
import KLinguaCore

struct CoursesView: View {
    @Environment(StudyStore.self) private var store

    var body: some View {
        let _ = store.revision
        let currentID = store.currentLesson?.id
        List {
            ForEach(store.library.units) { unit in
                Section {
                    if unit.available {
                        ForEach(unit.lessons) { lesson in
                            NavigationLink {
                                LessonView(lesson: lesson)
                            } label: {
                                LessonRow(lesson: lesson, status: store.status(of: lesson), isCurrent: lesson.id == currentID)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(unit.summary).font(.subheadline)
                            Label("尚未開放：教材撰寫中", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("第 \(unit.number) 單元・\(unit.title)")
                } footer: {
                    Text("階段 \(unit.stage.rawValue)：\(unit.stage.title)")
                }
            }
        }
        .navigationTitle("課程")
    }
}

struct LessonRow: View {
    let lesson: Lesson
    let status: StudyStore.LessonStatus
    let isCurrent: Bool

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(lesson.title).font(.headline)
                Text("\(lesson.vocabulary.count) 個單字・約 \(lesson.estimatedMinutes) 分鐘").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Text("目前").font(.caption.bold()).foregroundStyle(.tint)
            }
        }
    }

    private var icon: String {
        switch status {
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .completed: "checkmark.circle.fill"
        case .skippedByTest: "forward.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .notStarted: .secondary
        case .inProgress: .orange
        case .completed: .green
        case .skippedByTest: .blue
        }
    }
}

/// 一課的十個組成：目標、單字、發音、文法、例句、聽力、句型練習、口說、單字測驗、課後測驗（含完成條件）
struct LessonView: View {
    @Environment(StudyStore.self) private var store
    let lesson: Lesson

    var body: some View {
        let _ = store.revision
        let lp = store.existingProgress(for: lesson.id)
        List {
            Section("學習目標") {
                ForEach(lesson.objectives, id: \.self) { Label($0, systemImage: "target") }
            }
            Section("單字（\(lesson.vocabulary.count)）") {
                ForEach(lesson.vocabulary) { word in
                    NavigationLink {
                        VocabularyDetailView(word: word)
                    } label: {
                        KoreanLine(korean: word.korean, romanization: word.romanization, chinese: word.chinese, font: .body)
                    }
                }
            }
            Section("發音重點") {
                ForEach(lesson.pronunciation) { point in
                    NavigationLink(point.title) { PronunciationPointView(point: point) }
                }
            }
            Section("文法") {
                ForEach(lesson.grammar) { g in
                    NavigationLink { GrammarPointView(point: g) } label: {
                        VStack(alignment: .leading) {
                            Text(g.title).font(.headline)
                            Text(g.pattern).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("例句") {
                ForEach(lesson.examples, id: \.self) { ex in
                    KoreanLine(korean: ex.korean, chinese: ex.chinese, font: .body)
                }
            }
            Section("練習") {
                NavigationLink { ListeningPracticeView(lesson: lesson) } label: {
                    Label("聽力練習（\(lesson.listening.count) 題）", systemImage: "ear")
                }
                NavigationLink { DrillSetListView(lesson: lesson) } label: {
                    Label("句型練習 Pattern Drill（\(lesson.drills.count) 組）", systemImage: "repeat")
                }
                NavigationLink { ProductionDrillView(config: .speaking(lesson)) } label: {
                    Label("情境對話（離線腳本）", systemImage: "bubble.left.and.bubble.right")
                }
                NavigationLink { VocabularyQuizView(lesson: lesson) } label: {
                    Label("單字記憶測驗", systemImage: "checklist")
                }
                NavigationLink { PostTestView(lesson: lesson) } label: {
                    Label("課後測驗（\(lesson.postTest.count) 題）", systemImage: "graduationcap")
                }
            }
            completionSection(lp)
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func completionSection(_ lp: LessonProgress?) -> some View {
        let c = lesson.completion
        Section {
            criterion("課後測驗 ≥ \(percent(c.postTestPassRatio))",
                      value: lp?.postTestBestRatio.map { "最佳 \(percent($0))" } ?? "尚未測驗",
                      met: (lp?.postTestBestRatio ?? 0) >= c.postTestPassRatio)
            criterion("句型練習正確率 ≥ \(percent(c.drillAccuracy))",
                      value: lp?.drillAccuracy.map { percent($0) } ?? "尚未練習",
                      met: (lp?.drillAccuracy ?? 0) >= c.drillAccuracy)
            if c.requireVocabularyQuiz {
                criterion("完成單字記憶測驗", value: lp?.vocabularyQuizDone == true ? "已完成" : "尚未完成",
                          met: lp?.vocabularyQuizDone == true)
            }
            if lp?.skippedByTest == true {
                Label("已由診斷測驗跳過（仍可隨時複習）", systemImage: "forward.circle.fill").foregroundStyle(.blue)
            } else if lp?.completedAt != nil {
                Label("本課已完成", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                Button("完成本課，前往下一課") {
                    _ = store.completeLessonIfEligible(lesson)
                }
                .disabled(!(lp?.meetsCompletion(c) ?? false))
            }
        } header: {
            Text("完成條件")
        }
    }

    private func criterion(_ title: String, value: String, met: Bool) -> some View {
        HStack {
            Image(systemName: met ? "checkmark.circle.fill" : "circle").foregroundStyle(met ? Color.green : Color.secondary)
            Text(title)
            Spacer()
            Text(value).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func percent(_ v: Double) -> String { v.formatted(.percent.precision(.fractionLength(0))) }
}

struct PronunciationPointView: View {
    let point: PronunciationPoint

    var body: some View {
        List {
            Section("說明") { Text(point.explanation) }
            Section("嘴型與舌位") { Text(point.articulation) }
            if let pitfall = point.chineseSpeakerPitfall {
                Section("中文母語者常見問題") { Text(pitfall).foregroundStyle(.orange) }
            }
            Section("示範音") {
                ForEach(point.samples, id: \.self) { s in
                    HStack {
                        Text(s).font(.title2)
                        Spacer()
                        SpeakButton(text: s, slow: true)
                        SpeakButton(text: s)
                    }
                }
            }
            if !point.minimalPairs.isEmpty {
                Section("最小對立音") {
                    ForEach(point.minimalPairs, id: \.self) { pair in
                        HStack {
                            Text(pair.a).font(.title2)
                            SpeakButton(text: pair.a)
                            Text("／")
                            Text(pair.b).font(.title2)
                            SpeakButton(text: pair.b)
                            Spacer()
                            Text(pair.contrast).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Text("示範音由 iOS 合成語音產生，不是真人錄音。錄下自己的發音並比對的功能在第三階段加入。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(point.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GrammarPointView: View {
    let point: GrammarPoint

    var body: some View {
        List {
            Section("句型") {
                Text(point.pattern).font(.title3.bold())
                if let level = point.speechLevel {
                    Text(level.title).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("說明") { Text(point.explanation) }
            Section("例句") {
                ForEach(point.examples, id: \.self) { ex in
                    KoreanLine(korean: ex.korean, chinese: ex.chinese, font: .body)
                }
            }
        }
        .navigationTitle(point.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VocabularyQuizView: View {
    @Environment(StudyStore.self) private var store
    let lesson: Lesson
    @State private var result: (correct: Int, total: Int)?
    @State private var added = 0

    var body: some View {
        Group {
            if let result {
                SessionSummaryView(title: "單字記憶測驗完成", correct: result.correct, total: result.total,
                                   note: added > 0 ? "已把本課 \(added) 個新單字加入單字卡，之後由 SRS 安排複習。" : "本課單字都已在單字卡中。")
            } else {
                QuizRunnerView(questions: DistractorPicker.meaningQuiz(for: lesson.vocabulary, pool: store.library.allVocabulary,
                                                                     seed: SeededGenerator.seed(lesson.id)),
                               onAnswer: { q, correct, seconds in
                                   store.recordQuiz(q, correct: correct, responseSeconds: seconds, activity: .newVocabulary)
                               },
                               onFinish: { logs in
                                   let before = store.cards().count
                                   store.recordVocabularyQuiz(lesson: lesson)
                                   added = store.cards().count - before
                                   result = (logs.filter(\.correct).count, logs.count)
                               })
            }
        }
        .navigationTitle("單字記憶測驗")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PostTestView: View {
    @Environment(StudyStore.self) private var store
    let lesson: Lesson
    @State private var result: (correct: Int, total: Int)?
    @State private var completed = false

    var body: some View {
        Group {
            if let result {
                VStack {
                    SessionSummaryView(title: "課後測驗完成", correct: result.correct, total: result.total,
                                       note: completed ? "已達成本課完成條件，已前往下一課。" : "完成條件：課後測驗、句型練習正確率與單字記憶測驗都要達標。可回課程頁查看還差哪一項。")
                }
            } else {
                QuizRunnerView(questions: lesson.postTest,
                               onAnswer: { q, correct, seconds in
                                   store.recordQuiz(q, correct: correct, responseSeconds: seconds, activity: .dailyCheck)
                               },
                               onFinish: { logs in
                                   let correct = logs.filter(\.correct).count
                                   store.recordPostTest(lesson: lesson, correct: correct, total: logs.count)
                                   let alreadyDone = store.existingProgress(for: lesson.id)?.completedAt != nil
                                   completed = !alreadyDone && store.completeLessonIfEligible(lesson)
                                   result = (correct, logs.count)
                               })
            }
        }
        .navigationTitle("課後測驗")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ListeningPracticeView: View {
    @Environment(StudyStore.self) private var store
    let lesson: Lesson
    @State private var result: (correct: Int, total: Int)?
    @State private var startedAt = Date()

    var body: some View {
        Group {
            if let result {
                SessionSummaryView(title: "聽力練習完成", correct: result.correct, total: result.total,
                                   note: "音檔由 iOS 韓語合成語音朗讀。")
            } else {
                QuizRunnerView(questions: lesson.listening.map(\.asQuizQuestion),
                               onAnswer: { q, correct, seconds in
                                   store.recordQuiz(q, correct: correct, responseSeconds: seconds, activity: .listening)
                               },
                               onFinish: { logs in
                                   store.logActivity(.listening, seconds: Date().timeIntervalSince(startedAt))
                                   result = (logs.filter(\.correct).count, logs.count)
                               })
            }
        }
        .navigationTitle("聽力・\(lesson.title)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startedAt = Date() }
    }
}
