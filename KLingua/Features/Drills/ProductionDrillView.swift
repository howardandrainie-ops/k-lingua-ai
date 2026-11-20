import SwiftUI
import KLinguaCore

/// 輸出型練習（FSI Pattern Drill、離線口說腳本共用）。
///
/// 思考時間的計算：從提示出現到「開始輸入第一個字」為止，不含打字時間。
/// 第三階段改為語音作答後，會改成到「開始說話」為止。
struct ProductionDrillView: View {
    struct Config {
        var drillID: String
        var title: String
        var instruction: String
        var model: ExampleSentence?
        var items: [DrillItem]
        var initialThinkSeconds: Double
        /// 自由造句：答案不只一種，離線只能比對參考答案
        var isFreeProduction: Bool
        var lessonID: String?
        var skill: SkillDimension
        var activity: TrainingActivity
    }

    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let config: Config

    @State private var index = 0
    @State private var historyStreak = 0
    @State private var sessionStreak = 0
    @State private var shownAt = Date()
    @State private var firstKeyAt: Date?
    @State private var typed = ""
    @State private var grade: DrillGrade?
    @State private var unscored = false
    @State private var showCueText = false
    @State private var scored = 0
    @State private var correct = 0
    @State private var startedAt = Date()
    @State private var finished = false
    @State private var loaded = false
    @FocusState private var focused: Bool

    private var timeLimit: Double {
        DrillGrader.timeLimit(initial: config.initialThinkSeconds, fluentStreak: (historyStreak + sessionStreak) / 2)
    }

    var body: some View {
        Group {
            if finished {
                VStack {
                    SessionSummaryView(title: "\(config.title) 完成", correct: correct, total: scored,
                                       note: config.isFreeProduction ? "自由造句只有和參考答案相符時才計分；其他句子需要 AI 批改（第四階段）。" : nil)
                    Button("返回") { dismiss() }.buttonStyle(.borderedProminent)
                }
            } else if config.items.isEmpty {
                ContentUnavailableView("沒有題目", systemImage: "questionmark.circle")
            } else {
                drillBody(config.items[index])
            }
        }
        .navigationTitle(config.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            startedAt = Date()
            if let set = store.library.allLessons.lazy.flatMap(\.drills).first(where: { $0.id == config.drillID }) {
                historyStreak = store.drillFluentStreak(for: set)
            }
            present(0)
        }
    }

    private func drillBody(_ item: DrillItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("第 \(index + 1) / \(config.items.count) 題")
                    Spacer()
                    Text("思考時間 \(Int(timeLimit)) 秒")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(config.instruction).font(.subheadline)

                if let model = config.model {
                    GroupBox("示範句") {
                        KoreanLine(korean: model.korean, chinese: model.chinese, font: .body)
                    }
                }

                GroupBox("提示") {
                    HStack {
                        if item.cueIsAudio == true && !showCueText && grade == nil && !unscored {
                            Button("顯示文字") { showCueText = true }
                        } else {
                            Text(item.cue).font(.title2.bold())
                        }
                        Spacer()
                        if item.cueIsAudio == true {
                            SpeakButton(text: item.cue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if grade == nil && !unscored {
                    countdown
                }

                TextField("用韓文回答", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { submit(item) }
                    .disabled(grade != nil || unscored)
                    .onChange(of: typed) { _, newValue in
                        if firstKeyAt == nil && !newValue.isEmpty { firstKeyAt = Date() }
                    }

                if grade == nil && !unscored {
                    HStack {
                        Button("送出") { submit(item) }
                            .buttonStyle(.borderedProminent)
                            .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                        Button("不會") { giveUp(item) }
                    }
                } else {
                    result(item)
                }
            }
            .padding()
        }
    }

    private var countdown: some View {
        TimelineView(.periodic(from: shownAt, by: 0.2)) { context in
            let thinking = (firstKeyAt ?? context.date).timeIntervalSince(shownAt)
            let remaining = timeLimit - thinking
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: max(0, min(timeLimit, remaining)), total: timeLimit)
                    .tint(remaining > 0 ? Color.accentColor : Color.red)
                Text(firstKeyAt != nil ? "已開始作答（思考 \(String(format: "%.1f", thinking)) 秒）"
                     : remaining > 0 ? "剩 \(Int(remaining.rounded(.up))) 秒開始作答" : "超過思考時間，仍可作答")
                    .font(.caption)
                    .foregroundStyle(remaining > 0 ? Color.secondary : Color.red)
            }
        }
    }

    @ViewBuilder
    private func result(_ item: DrillItem) -> some View {
        if let grade {
            FeedbackBanner(correct: grade.verdict.isAcceptable, title: grade.verdict.title, detail: grade.feedback)
            Text("思考 \(grade.responseSeconds, format: .number.precision(.fractionLength(1))) 秒（限時 \(Int(timeLimit)) 秒）\(grade.withinTimeLimit ? "" : "・超時")")
                .font(.caption)
                .foregroundStyle(grade.withinTimeLimit ? Color.secondary : Color.orange)
        } else if unscored {
            FeedbackBanner(correct: true, title: "參考答案",
                           detail: "自由造句有很多種正確說法，離線無法判斷你的句子，本題不計分。請對照參考答案自行檢查。")
        }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(item.answers, id: \.self) { answer in
                KoreanLine(korean: answer, font: .body)
            }
            Text(item.chinese).font(.subheadline).foregroundStyle(.secondary)
        }
        Button(index + 1 < config.items.count ? "下一題" : "完成") { advance() }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
    }

    private func present(_ i: Int) {
        index = i
        typed = ""
        grade = nil
        unscored = false
        firstKeyAt = nil
        showCueText = false
        shownAt = Date()
        focused = true
        let item = config.items[i]
        if item.cueIsAudio == true {
            Speaker.shared.speak(item.cue)
        }
    }

    private func submit(_ item: DrillItem) {
        let response = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !response.isEmpty, grade == nil, !unscored else { return }
        let thinking = (firstKeyAt ?? Date()).timeIntervalSince(shownAt)
        let g = DrillGrader.grade(response: response, answers: item.answers, responseSeconds: thinking, timeLimit: timeLimit)
        if config.isFreeProduction && !g.verdict.isAcceptable {
            unscored = true
        } else {
            record(g, userAnswer: response)
        }
        focused = false
        Speaker.shared.speak(item.answers.first ?? "")
    }

    private func giveUp(_ item: DrillItem) {
        let thinking = Date().timeIntervalSince(shownAt)
        var g = DrillGrader.grade(response: "", answers: item.answers, responseSeconds: thinking, timeLimit: timeLimit)
        g.verdict = .incorrect
        g.withinTimeLimit = false
        g.feedback = "先聽正確答案，跟著唸兩次。"
        record(g, userAnswer: "")
        focused = false
        Speaker.shared.speak(item.answers.first ?? "")
    }

    private func record(_ g: DrillGrade, userAnswer: String) {
        grade = g
        scored += 1
        if g.verdict.isAcceptable { correct += 1 }
        if g.verdict.isAcceptable && g.withinTimeLimit { sessionStreak += 1 } else { sessionStreak = 0; historyStreak = 0 }
        store.recordDrill(drillID: config.drillID, grade: g, userAnswer: userAnswer, lessonID: config.lessonID,
                          skill: config.skill, activity: config.activity)
    }

    private func advance() {
        if index + 1 < config.items.count {
            present(index + 1)
        } else {
            finished = true
            store.logActivity(config.activity, seconds: Date().timeIntervalSince(startedAt))
        }
    }
}

extension ProductionDrillView.Config {
    static func drill(_ set: DrillSet, lessonID: String?) -> Self {
        .init(drillID: set.id, title: set.type.title, instruction: set.instruction, model: set.model, items: set.items,
              initialThinkSeconds: set.thinkSeconds, isFreeProduction: set.type == .freeProduction,
              lessonID: lessonID, skill: set.type == .freeProduction ? .speaking : .grammar, activity: .patternDrill)
    }

    static func speaking(_ lesson: Lesson) -> Self {
        .init(drillID: "\(lesson.id)-speaking", title: "情境對話（離線）",
              instruction: "\(lesson.speaking.scenario)\n語體：\(lesson.speaking.speechLevel.title)",
              model: nil, items: lesson.speaking.offlineScript, initialThinkSeconds: 8, isFreeProduction: false,
              lessonID: nil, skill: .speaking, activity: .scenarioRoleplay)
    }
}

/// 一課的所有 Pattern Drill
struct DrillSetListView: View {
    @Environment(StudyStore.self) private var store
    let lesson: Lesson

    var body: some View {
        let _ = store.revision
        let lp = store.existingProgress(for: lesson.id)
        List {
            Section {
                ForEach(lesson.drills) { set in
                    NavigationLink {
                        ProductionDrillView(config: .drill(set, lessonID: lesson.id))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(set.type.title).font(.headline)
                            Text(set.instruction).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text("\(set.items.count) 題・初始思考 \(Int(set.thinkSeconds)) 秒").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("思考時間從提示出現算到你開始輸入為止；連續流暢答對後會逐步縮短，最短 3 秒。")
            }
            if let accuracy = lp?.drillAccuracy {
                Section {
                    LabeledContent("本課句型練習正確率", value: accuracy.formatted(.percent.precision(.fractionLength(0))))
                }
            }
        }
        .navigationTitle("句型練習・\(lesson.title)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
