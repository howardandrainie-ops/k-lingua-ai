import SwiftUI
import KLinguaCore

/// SRS 複習：同一個單字的四個面向分開排程、分開出題。
/// - 中文理解：看韓文想意思 → 自評（記得／部分／忘記）
/// - 韓文辨識：看中文選韓文（客觀評分）
/// - 聽力辨識：聽語音選中文（客觀評分）
/// - 口語輸出：看中文打出韓文（客觀評分；第三階段改為說出來）
struct ReviewSessionView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var limit = 100

    @State private var queue: [FacetSchedule] = []
    @State private var index = 0
    @State private var loaded = false
    @State private var startedAt = Date()
    @State private var shownAt = Date()
    @State private var firstKeyAt: Date?
    @State private var options: [VocabularyItem] = []
    @State private var revealed = false
    @State private var chosen: VocabularyItem?
    @State private var typed = ""
    @State private var outcome: ReviewOutcome?
    @State private var feedbackText: String?
    @State private var correctCount = 0
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if queue.isEmpty {
                ContentUnavailableView("目前沒有到期的複習", systemImage: "checkmark.seal",
                                       description: Text("新單字學過後會立刻進入複習；之後依記憶狀況在 1、3、7、30、90 天後再出現。"))
            } else if finished {
                VStack {
                    SessionSummaryView(title: "複習完成", correct: correctCount, total: queue.count)
                    Button("返回") { dismiss() }.buttonStyle(.borderedProminent)
                }
            } else if let word = store.vocabulary(for: queue[index]) {
                card(queue[index], word)
            } else {
                // 教材中已找不到這個單字（例如教材更新），略過
                ProgressView().onAppear { advance() }
            }
        }
        .navigationTitle(finished || queue.isEmpty ? "SRS 複習" : "複習 \(index + 1) / \(queue.count)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            queue = store.dueSchedules(limit: limit)
            loaded = true
            startedAt = Date()
            if !queue.isEmpty { prepare() }
        }
    }

    // MARK: - 卡片

    private func card(_ schedule: FacetSchedule, _ word: VocabularyItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(schedule.facet.title)
                    Spacer()
                    Text((LeitnerBox(rawValue: schedule.boxRaw) ?? .box1).shortTitle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                switch schedule.facet {
                case .meaning: meaningCard(word)
                case .recognition: choiceCard(prompt: word.chinese, word: word, label: \.korean)
                case .listening: listeningCard(word)
                case .production: productionCard(word)
                }

                if outcome != nil {
                    answerDetail(word)
                    Button(index + 1 < queue.count ? "下一張" : "完成") { advance() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }

    private func meaningCard(_ word: VocabularyItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("這個字是什麼意思？").font(.subheadline).foregroundStyle(.secondary)
            KoreanLine(korean: word.korean, romanization: word.romanization, font: .largeTitle)
            if !revealed {
                Button("顯示答案") {
                    revealed = true
                    firstKeyAt = Date()
                }
                .buttonStyle(.borderedProminent)
            } else if outcome == nil {
                Text(word.chinese).font(.title2.bold())
                Text("你剛剛想起來了嗎？（自我評估）").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("記得") { selfGrade(.init(correct: true, responseSeconds: thinkingSeconds)) }
                        .buttonStyle(.borderedProminent).tint(.green)
                    Button("部分記得") { selfGrade(.init(correct: false, responseSeconds: thinkingSeconds, error: .partial)) }
                        .buttonStyle(.bordered)
                    Button("忘記了") { selfGrade(.init(correct: false, responseSeconds: thinkingSeconds, error: .forgotten)) }
                        .buttonStyle(.bordered).tint(.red)
                }
            }
        }
    }

    private func choiceCard(prompt: String, word: VocabularyItem, label: KeyPath<VocabularyItem, String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt).font(.largeTitle.bold())
            ForEach(options) { option in
                Button {
                    choose(option, target: word)
                } label: {
                    Text(option[keyPath: label]).font(.title3).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(tint(option, word))
                .disabled(outcome != nil)
            }
        }
    }

    private func listeningCard(_ word: VocabularyItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 24) {
                Button { Speaker.shared.speak(word.korean) } label: { Label("再聽一次", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(.bordered)
                Button { Speaker.shared.speak(word.korean, slow: true) } label: { Label("慢速", systemImage: "tortoise.fill") }
                    .buttonStyle(.bordered)
            }
            Text("聽到的是哪個意思？").font(.subheadline).foregroundStyle(.secondary)
            ForEach(options) { option in
                Button {
                    choose(option, target: word)
                } label: {
                    Text(option.chinese).font(.title3).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(tint(option, word))
                .disabled(outcome != nil)
            }
        }
    }

    private func productionCard(_ word: VocabularyItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(word.chinese).font(.largeTitle.bold())
            Text("用韓文寫出來（第三階段改為說出來）").font(.caption).foregroundStyle(.secondary)
            TextField("輸入韓文", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit { submitProduction(word) }
                .disabled(outcome != nil)
                .onChange(of: typed) { _, v in if firstKeyAt == nil && !v.isEmpty { firstKeyAt = Date() } }
            if outcome == nil {
                HStack {
                    Button("送出") { submitProduction(word) }
                        .buttonStyle(.borderedProminent)
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    Button("想不起來") {
                        selfGrade(.init(correct: false, responseSeconds: thinkingSeconds, error: .forgotten))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func answerDetail(_ word: VocabularyItem) -> some View {
        if let outcome {
            FeedbackBanner(correct: outcome.correct, title: outcome.correct ? "正確" : "再加強", detail: feedbackText)
        }
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                KoreanLine(korean: word.korean, romanization: word.romanization, pronunciation: word.pronunciation, chinese: word.chinese)
                Divider()
                KoreanLine(korean: word.example.korean, chinese: word.example.chinese, font: .body)
                if let mistake = word.commonMistake {
                    Text("常見錯誤：\(mistake)").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - 作答

    private var thinkingSeconds: Double { (firstKeyAt ?? Date()).timeIntervalSince(shownAt) }

    private func tint(_ option: VocabularyItem, _ word: VocabularyItem) -> Color? {
        guard outcome != nil else { return nil }
        if option.id == word.id { return .green }
        if option.id == chosen?.id { return .red }
        return .gray
    }

    private func prepare() {
        guard index < queue.count, let word = store.vocabulary(for: queue[index]) else { return }
        revealed = false
        chosen = nil
        typed = ""
        outcome = nil
        feedbackText = nil
        firstKeyAt = nil
        shownAt = Date()
        var rng = SeededGenerator(seed: SeededGenerator.seed("\(word.id)-\(queue[index].facetRaw)-\(Date().timeIntervalSince1970)"))
        switch queue[index].facet {
        case .recognition:
            options = DistractorPicker.options(for: word, pool: store.library.allVocabulary, label: \.korean, using: &rng)
        case .listening:
            options = DistractorPicker.options(for: word, pool: store.library.allVocabulary, label: \.chinese, using: &rng)
            Speaker.shared.speak(word.korean)
        case .production:
            options = []
            focused = true
        case .meaning:
            options = []
        }
    }

    private func choose(_ option: VocabularyItem, target: VocabularyItem) {
        guard outcome == nil else { return }
        chosen = option
        let seconds = Date().timeIntervalSince(shownAt)
        if option.id == target.id {
            finish(ReviewOutcome(correct: true, responseSeconds: seconds), feedback: nil)
        } else {
            let error = RecallClassifier.errorForWrongChoice(targetKorean: target.korean, chosenKorean: option.korean)
            let note = error == .confusedWithSimilar ? "你選的「\(option.korean)」和「\(target.korean)」字形或發音很接近，注意分辨。" : nil
            finish(ReviewOutcome(correct: false, responseSeconds: seconds, error: error), feedback: note)
        }
        if queue[index].facet == .recognition { Speaker.shared.speak(target.korean) }
    }

    private func submitProduction(_ word: VocabularyItem) {
        let response = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard outcome == nil, !response.isEmpty else { return }
        let grade = DrillGrader.grade(response: response, answers: [word.korean], responseSeconds: thinkingSeconds, timeLimit: .infinity)
        focused = false
        finish(grade.reviewOutcome, feedback: grade.verdict == .correct ? nil : grade.feedback)
        Speaker.shared.speak(word.korean)
    }

    private func selfGrade(_ o: ReviewOutcome) {
        focused = false
        finish(o, feedback: nil)
    }

    private func finish(_ o: ReviewOutcome, feedback: String?) {
        outcome = o
        feedbackText = feedback
        if o.correct { correctCount += 1 }
        store.recordReview(queue[index], outcome: o)
    }

    private func advance() {
        if index + 1 < queue.count {
            index += 1
            prepare()
        } else {
            finished = true
            store.logActivity(.srsReview, seconds: Date().timeIntervalSince(startedAt), reviews: queue.count)
        }
    }
}
