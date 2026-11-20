import SwiftUI
import KLinguaCore

extension TrainingActivity {
    /// 尚未能執行的項目與原因（不顯示假的練習）
    var unavailableReason: String? {
        switch self {
        case .rapidResponse: "快速反應需要語音作答，第三階段開放。"
        case .aiConversation: "AI 口語對話需要設定 AI 服務，第四階段開放。"
        default: nil
        }
    }

    var systemImage: String {
        switch self {
        case .newVocabulary: "plus.rectangle.on.rectangle"
        case .pronunciationDiscrimination: "waveform"
        case .srsReview: "rectangle.stack"
        case .patternDrill: "repeat"
        case .rapidResponse: "bolt"
        case .aiConversation: "sparkles"
        case .scenarioRoleplay: "bubble.left.and.bubble.right"
        case .listening: "ear"
        case .minimalPairs: "arrow.left.arrow.right"
        case .mistakeReview: "exclamationmark.bubble"
        case .dailyCheck: "checkmark.seal"
        }
    }
}

/// 今日訓練：依可用時間、到期量、錯誤數與弱項自動生成
struct TodayView: View {
    @Environment(StudyStore.self) private var store

    var body: some View {
        let _ = store.revision
        let now = Date()
        let plan = store.todayPlan(at: now)
        let done = store.completedToday(at: now)
        let measured = store.skillEstimates(at: now).filter { $0.score != nil }
        List {
            Section {
                LabeledContent("今日時間", value: "\(store.profile().dailyMinutes) 分鐘")
                LabeledContent("已完成", value: "\(plan.filter { done.contains($0.activity) }.count) / \(plan.count) 項")
            } footer: {
                Text(measured.isEmpty
                     ? "能力資料還不夠（每項至少 5 題），目前用標準比例分配時間。"
                     : "已依 \(measured.count) 項能力的實測結果，把較多時間分給較弱的能力。")
            }
            ForEach(TrainingSession.allCases, id: \.self) { session in
                let blocks = plan.filter { $0.session == session }
                if !blocks.isEmpty {
                    Section(session.title) {
                        ForEach(blocks, id: \.activity) { block in
                            row(block, done: done.contains(block.activity))
                        }
                    }
                }
            }
        }
        .navigationTitle("今日訓練")
    }

    @ViewBuilder
    private func row(_ block: PlannedBlock, done: Bool) -> some View {
        let label = HStack {
            Image(systemName: done ? "checkmark.circle.fill" : block.activity.systemImage)
                .foregroundStyle(done ? Color.green : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(block.activity.title)
                if let reason = block.activity.unavailableReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(block.minutes) 分").monospacedDigit().foregroundStyle(.secondary)
        }
        if block.activity.unavailableReason != nil {
            label.opacity(0.6)
        } else {
            NavigationLink { destination(block) } label: { label }
        }
    }

    @ViewBuilder
    private func destination(_ block: PlannedBlock) -> some View {
        let lesson = store.currentLesson
        switch block.activity {
        case .newVocabulary:
            NewWordsView(count: max(3, min(12, block.minutes)))
        case .srsReview:
            ReviewSessionView(limit: max(10, Int(Double(block.minutes) / DailyPlanner.minutesPerReview)))
        case .patternDrill:
            if let lesson { DrillSetListView(lesson: lesson) } else { noLesson }
        case .scenarioRoleplay:
            if let lesson { ProductionDrillView(config: .speaking(lesson)) } else { noLesson }
        case .listening:
            if let lesson { ListeningPracticeView(lesson: lesson) } else { noLesson }
        case .pronunciationDiscrimination:
            DiscriminationView(mode: .sounds)
        case .minimalPairs:
            DiscriminationView(mode: .minimalPairs)
        case .mistakeReview:
            MistakesView()
        case .dailyCheck:
            DailyCheckView()
        case .rapidResponse, .aiConversation:
            NotYetAvailableView(title: block.activity.title, reason: block.activity.unavailableReason ?? "")
        }
    }

    private var noLesson: some View {
        ContentUnavailableView("沒有可用的課程", systemImage: "book.closed")
    }
}

/// 聽音辨識（只用 TTS，不需要語音辨識）
struct DiscriminationView: View {
    enum Mode { case sounds, minimalPairs }

    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var count = 10

    @State private var questions: [DiscriminationQuestion] = []
    @State private var index = 0
    @State private var chosen: Int?
    @State private var correct = 0
    @State private var shownAt = Date()
    @State private var startedAt = Date()
    @State private var loaded = false
    @State private var finished = false

    private var activity: TrainingActivity { mode == .sounds ? .pronunciationDiscrimination : .minimalPairs }

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if questions.isEmpty {
                ContentUnavailableView("目前課程沒有這類題目", systemImage: "waveform")
            } else if finished {
                VStack {
                    SessionSummaryView(title: "\(activity.title)完成", correct: correct, total: questions.count,
                                       note: "語音由 iOS 合成，與真人發音略有差異。現代首爾口語中 ㅐ／ㅔ 幾乎不分，這類題目不列入。")
                    Button("返回") { dismiss() }.buttonStyle(.borderedProminent)
                }
            } else {
                questionView(questions[index])
            }
        }
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let points = store.lessonsUpToCurrent.flatMap(\.pronunciation)
            let seed = SeededGenerator.seed("\(activity.rawValue)-\(Date().timeIntervalSince1970)")
            questions = mode == .sounds
                ? DiscriminationBuilder.sounds(points, count: count, seed: seed)
                : DiscriminationBuilder.minimalPairs(points, count: count, seed: seed)
            startedAt = Date()
            present()
        }
    }

    private func questionView(_ q: DiscriminationQuestion) -> some View {
        VStack(spacing: 20) {
            Text("第 \(index + 1) / \(questions.count) 題・\(q.focus)").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                Button { Speaker.shared.speak(q.audio) } label: { Label("再聽一次", systemImage: "speaker.wave.2.fill") }
                Button { Speaker.shared.speak(q.audio, slow: true) } label: { Label("慢速", systemImage: "tortoise.fill") }
            }
            .buttonStyle(.bordered)
            Text("你聽到的是？").font(.title3)
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                Button {
                    choose(i, q)
                } label: {
                    Text(option).font(.largeTitle).frame(maxWidth: .infinity, minHeight: 60)
                }
                .buttonStyle(.bordered)
                .tint(chosen == nil ? nil : i == q.answerIndex ? Color.green : i == chosen ? Color.red : Color.gray)
                .disabled(chosen != nil)
            }
            if chosen != nil {
                HStack {
                    ForEach(q.options, id: \.self) { option in
                        Button("聽「\(option)」") { Speaker.shared.speak(option) }
                    }
                }
                .buttonStyle(.bordered)
                Button(index + 1 < questions.count ? "下一題" : "完成") { advance() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
    }

    private func present() {
        chosen = nil
        shownAt = Date()
        if index < questions.count { Speaker.shared.speak(questions[index].audio) }
    }

    private func choose(_ i: Int, _ q: DiscriminationQuestion) {
        guard chosen == nil else { return }
        chosen = i
        let ok = i == q.answerIndex
        if ok { correct += 1 }
        store.recordAttempt(skill: .phonemeDiscrimination, activity: activity, sourceID: q.id,
                            correct: ok, responseSeconds: Date().timeIntervalSince(shownAt))
    }

    private func advance() {
        if index + 1 < questions.count {
            index += 1
            present()
        } else {
            finished = true
            store.logActivity(activity, seconds: Date().timeIntervalSince(startedAt))
        }
    }
}

/// 當日能力測驗：從已學課程的課後測驗抽題，涵蓋不同能力
struct DailyCheckView: View {
    @Environment(StudyStore.self) private var store
    @State private var questions: [QuizQuestion] = []
    @State private var loaded = false
    @State private var startedAt = Date()
    @State private var result: (correct: Int, total: Int)?

    var body: some View {
        Group {
            if let result {
                SessionSummaryView(title: "今日測驗完成", correct: result.correct, total: result.total,
                                   note: "結果已計入各項能力分數。")
            } else if loaded {
                QuizRunnerView(questions: questions,
                               onAnswer: { q, correct, seconds in
                                   store.recordQuiz(q, correct: correct, responseSeconds: seconds, activity: .dailyCheck)
                               },
                               onFinish: { logs in
                                   store.logActivity(.dailyCheck, seconds: Date().timeIntervalSince(startedAt))
                                   result = (logs.filter(\.correct).count, logs.count)
                               })
            } else {
                ProgressView()
            }
        }
        .navigationTitle("當日能力測驗")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            questions = DailyCheckBuilder.questions(from: store.lessonsUpToCurrent, count: 6,
                                                    seed: SeededGenerator.seed("daily-\(Date().timeIntervalSince1970)"))
            startedAt = Date()
            loaded = true
        }
    }
}

/// 錯誤本
struct MistakesView: View {
    @Environment(StudyStore.self) private var store
    @State private var startedAt = Date()

    var body: some View {
        let _ = store.revision
        let mistakes = store.openMistakes()
        List {
            if mistakes.isEmpty {
                ContentUnavailableView("沒有待複習的錯誤", systemImage: "checkmark.circle")
            }
            ForEach(mistakes) { m in
                VStack(alignment: .leading, spacing: 6) {
                    Text((DrillVerdict(rawValue: m.categoryRaw) ?? .incorrect).title)
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    if !m.userAnswer.isEmpty {
                        Text("你的答案：\(m.userAnswer)").strikethrough().foregroundStyle(.secondary)
                    }
                    KoreanLine(korean: m.expected, font: .body)
                    Text(m.explanation).font(.caption)
                    Button("我已經掌握了") { store.resolveMistake(m) }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
            if !mistakes.isEmpty {
                Section {
                    Button("完成今日錯誤複習") {
                        store.logActivity(.mistakeReview, seconds: Date().timeIntervalSince(startedAt))
                    }
                }
            }
        }
        .navigationTitle("錯誤複習")
        .onAppear { startedAt = Date() }
    }
}
