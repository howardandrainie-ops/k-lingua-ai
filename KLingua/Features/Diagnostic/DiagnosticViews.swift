import SwiftUI
import KLinguaCore

/// 首次啟動：診斷測驗說明
struct DiagnosticIntroView: View {
    @Environment(StudyStore.self) private var store

    var body: some View {
        let test = store.library.diagnostic
        List {
            Section {
                Text("先花約 \(test.estimatedMinutes) 分鐘做一次能力診斷，系統會依結果決定你從哪一課開始，並找出需要加強的能力。")
                Text("完全沒學過韓文也沒關係：不會的題目直接按「不知道」，不要猜，結果會更準確。")
                    .foregroundStyle(.secondary)
            }
            Section("測驗內容（共 \(test.sections.reduce(0) { $0 + $1.questions.count }) 題）") {
                ForEach(test.sections) { section in
                    LabeledContent(section.title, value: "\(section.questions.count) 題")
                }
            }
            if !Speaker.shared.hasKoreanVoice {
                Section {
                    Label("這台裝置找不到韓語語音，聽力題會沒有聲音。請到「設定 › 輔助使用 › 朗讀內容 › 聲音 › 韓文」下載後再開始。",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                NavigationLink {
                    DiagnosticRunView()
                } label: {
                    Label("開始診斷測驗", systemImage: "play.fill").font(.headline)
                }
            } footer: {
                Text("口說題目前用韓文鍵盤作答（語音作答在第三階段加入）。")
            }
        }
        .navigationTitle("能力診斷")
    }
}

struct DiagnosticRunView: View {
    @Environment(StudyStore.self) private var store
    @State private var startedAt = Date()
    @State private var correctIDs: Set<String> = []
    @State private var scores: [PlacementEngine.SectionScore] = []
    @State private var result: PlacementResult?

    var body: some View {
        let test = store.library.diagnostic
        Group {
            if let result {
                DiagnosticResultView(result: result, scores: scores, elapsed: Date().timeIntervalSince(startedAt))
            } else {
                QuizRunnerView(questions: test.sections.flatMap(\.questions), showsFeedback: false,
                               onAnswer: { q, correct, _ in
                                   if correct { correctIDs.insert(q.id) }
                               },
                               onFinish: { _ in
                                   scores = QuizScoring.sectionScores(test, correctIDs: correctIDs)
                                   result = PlacementEngine.place(scores)
                               })
                .safeAreaInset(edge: .top) {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        let elapsed = context.date.timeIntervalSince(startedAt)
                        Text("已用時間 \(Int(elapsed) / 60):\(String(format: "%02d", Int(elapsed) % 60))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(elapsed > Double(test.estimatedMinutes * 60) ? Color.orange : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(.bar)
                    }
                }
            }
        }
        .navigationTitle(result == nil ? "診斷測驗" : "診斷結果")
        .navigationBarBackButtonHidden(result != nil)
    }
}

struct DiagnosticResultView: View {
    @Environment(StudyStore.self) private var store
    let result: PlacementResult
    let scores: [PlacementEngine.SectionScore]
    let elapsed: Double

    var body: some View {
        let startUnit = store.library.units.first { $0.number == result.startUnitNumber }
        List {
            Section("建議起點") {
                LabeledContent("起始單元", value: "第 \(result.startUnitNumber) 單元")
                if let startUnit {
                    Text(startUnit.title).font(.headline)
                    if !startUnit.available {
                        Text("這個單元的教材還在撰寫中，先從目前已開放的最後一課開始，並在新單元開放後自動銜接。")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Text(result.reason)
            }
            Section {
                ForEach(scores, id: \.skill) { s in
                    let ratio = QuizScoring.ratio(correct: s.correct, total: s.total)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(s.skill.title)
                            Spacer()
                            Text("\(s.correct) / \(s.total)")
                                .monospacedDigit()
                                .foregroundStyle(ratio < PlacementEngine.weakThreshold ? Color.red : Color.primary)
                        }
                        ProgressView(value: ratio)
                            .tint(ratio < PlacementEngine.weakThreshold ? .red : .green)
                    }
                }
            } header: {
                Text("各部分答對題數")
            } footer: {
                Text("用時 \(formatMinutes(elapsed))。這是單次測驗的原始答對數，題數少，只用來決定起點；之後的能力分數會隨每天練習持續更新。")
            }
            if !result.weakSkills.isEmpty {
                Section("需要加強（答對率低於 60%）") {
                    Text(result.weakSkills.map(\.title).joined(separator: "、"))
                }
            }
            Section {
                Button {
                    store.applyPlacement(result, sectionScores: scores)
                } label: {
                    Label("依這個結果開始學習", systemImage: "arrow.right.circle.fill").font(.headline)
                }
            }
        }
    }
}
