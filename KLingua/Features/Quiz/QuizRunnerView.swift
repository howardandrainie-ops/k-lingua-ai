import SwiftUI
import KLinguaCore

struct QuizAnswerLog {
    let question: QuizQuestion
    let correct: Bool
    let seconds: Double
}

/// 通用測驗流程：診斷測驗、課後測驗、單字記憶測驗、聽力練習、每日測驗共用。
/// 每答一題就呼叫 onAnswer（由呼叫端寫入資料庫），全部答完呼叫 onFinish。
struct QuizRunnerView: View {
    let questions: [QuizQuestion]
    var showsFeedback = true
    let onAnswer: (QuizQuestion, Bool, Double) -> Void
    let onFinish: ([QuizAnswerLog]) -> Void

    @State private var index = 0
    @State private var logs: [QuizAnswerLog] = []
    @State private var shownAt = Date()
    @State private var typed = ""
    @State private var chosen: Int?
    @State private var answeredCorrect: Bool?
    @State private var gradeFeedback: String?
    @FocusState private var typingFocused: Bool

    var body: some View {
        if questions.isEmpty {
            ContentUnavailableView("沒有題目", systemImage: "questionmark.circle")
        } else if index < questions.count {
            questionView(questions[index])
                .id(index)
                .task(id: index) {
                    shownAt = Date()
                    if let audio = questions[index].audioText, questions[index].kind == .listeningChoice {
                        try? await Task.sleep(for: .milliseconds(300))
                        Speaker.shared.speak(audio)
                    }
                }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func questionView(_ q: QuizQuestion) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("第 \(index + 1) / \(questions.count) 題")
                        Spacer()
                        Text(q.skill.title)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ProgressView(value: Double(index), total: Double(questions.count))
                }

                Text(q.prompt).font(.title2.bold())

                if let audio = q.audioText {
                    HStack(spacing: 24) {
                        Button {
                            Speaker.shared.speak(audio)
                        } label: {
                            Label("播放", systemImage: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            Speaker.shared.speak(audio, slow: true)
                        } label: {
                            Label("慢速", systemImage: "tortoise.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                switch q.kind {
                case .choice, .listeningChoice:
                    choiceButtons(q)
                case .typing, .speaking:
                    typingInput(q)
                }

                if answeredCorrect == nil {
                    Button("不知道") { answer(q, .dontKnow) }
                        .foregroundStyle(.secondary)
                } else {
                    feedback(q)
                }
            }
            .padding()
        }
    }

    private func choiceButtons(_ q: QuizQuestion) -> some View {
        VStack(spacing: 10) {
            ForEach(Array((q.options ?? []).enumerated()), id: \.offset) { i, option in
                Button {
                    answer(q, .choice(i))
                } label: {
                    Text(option)
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(tint(for: i, q))
                .disabled(answeredCorrect != nil)
            }
        }
    }

    private func tint(for i: Int, _ q: QuizQuestion) -> Color? {
        guard answeredCorrect != nil else { return nil }
        if i == q.answerIndex { return .green }
        if i == chosen { return .red }
        return .gray
    }

    private func typingInput(_ q: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if q.kind == .speaking {
                Label("語音作答在第三階段加入。目前請用韓文鍵盤輸入你要說的句子。", systemImage: "keyboard")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            TextField("輸入韓文", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($typingFocused)
                .submitLabel(.done)
                .onSubmit { if !typed.isEmpty { answer(q, .text(typed)) } }
                .disabled(answeredCorrect != nil)
            if answeredCorrect == nil {
                Button("送出") { answer(q, .text(typed)) }
                    .buttonStyle(.borderedProminent)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { typingFocused = true }
    }

    @ViewBuilder
    private func feedback(_ q: QuizQuestion) -> some View {
        if showsFeedback {
            let correct = answeredCorrect ?? false
            FeedbackBanner(correct: correct, title: correct ? "答對了" : "正確答案：\(q.correctAnswerText)",
                           detail: [gradeFeedback, q.explanation].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n"))
            if let first = q.acceptedAnswers?.first ?? (q.kind == .listeningChoice ? q.audioText : nil) {
                HStack {
                    Text("聽正確發音").font(.subheadline)
                    SpeakButton(text: first)
                }
            }
        }
        Button(index + 1 < questions.count ? "下一題" : "完成") { next() }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
    }

    private func answer(_ q: QuizQuestion, _ response: QuizResponse) {
        guard answeredCorrect == nil else { return }
        let seconds = Date().timeIntervalSince(shownAt)
        let correct = QuizScoring.isCorrect(q, response: response)
        if case .choice(let i) = response { chosen = i }
        if case .text(let t) = response, let accepted = q.acceptedAnswers, !accepted.isEmpty {
            let grade = DrillGrader.grade(response: t, answers: accepted, responseSeconds: seconds, timeLimit: .infinity)
            gradeFeedback = grade.feedback
        }
        answeredCorrect = correct
        typingFocused = false
        logs.append(QuizAnswerLog(question: q, correct: correct, seconds: seconds))
        onAnswer(q, correct, seconds)
        if !showsFeedback { next() }
    }

    private func next() {
        typed = ""
        chosen = nil
        answeredCorrect = nil
        gradeFeedback = nil
        if index + 1 < questions.count {
            index += 1
        } else {
            index = questions.count
            onFinish(logs)
        }
    }
}
