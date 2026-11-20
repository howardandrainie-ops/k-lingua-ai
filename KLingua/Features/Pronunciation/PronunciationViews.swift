import SwiftUI
import KLinguaCore

/// 發音練習中心：依已學課程列出發音重點與跟讀句子
struct PronunciationHomeView: View {
    @Environment(StudyStore.self) private var store

    var body: some View {
        let _ = store.revision
        let lessons = store.lessonsUpToCurrent
        let recent = store.recentPronunciation(limit: 30)
        let judged = recent.filter { ($0.recognizedText ?? "").isEmpty == false }
        let matched = judged.filter { SpeechComparison.squash($0.recognizedText ?? "") == SpeechComparison.squash($0.target) }
        List {
            Section {
                Text(SpeechComparison.limitations).font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("說明")
            }
            if !judged.isEmpty {
                Section("最近 \(judged.count) 次錄音") {
                    LabeledContent("辨識結果與目標一致", value: "\(matched.count) / \(judged.count)")
                }
            }
            ForEach(Array(lessons.reversed())) { lesson in
                Section(lesson.title) {
                    ForEach(lesson.pronunciation) { point in
                        NavigationLink {
                            PronunciationPracticeView(title: point.title, focus: point.articulation,
                                                      targets: Self.targets(for: point))
                        } label: {
                            VStack(alignment: .leading) {
                                Text(point.title)
                                Text("\(Self.targets(for: point).count) 個練習音").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    NavigationLink {
                        PronunciationPracticeView(title: "句子跟讀", focus: "先聽示範句，再完整說一次。注意連音與語調。",
                                                  targets: lesson.examples.map(\.korean))
                    } label: {
                        Label("句子跟讀（\(lesson.examples.count) 句）", systemImage: "text.bubble")
                    }
                }
            }
        }
        .navigationTitle("發音練習")
    }

    /// 示範音＋最小對立音的兩邊（去重）
    static func targets(for point: PronunciationPoint) -> [String] {
        var out: [String] = []
        for t in point.samples + point.minimalPairs.flatMap({ [$0.a, $0.b] }) where !out.contains(t) {
            out.append(t)
        }
        return out
    }
}

/// 聽示範 → 錄音 → 辨識比對 → 重播自己的錄音
struct PronunciationPracticeView: View {
    @Environment(StudyStore.self) private var store
    let title: String
    let focus: String
    let targets: [String]

    @State private var index = 0
    @State private var check: PronunciationCheck?
    @State private var capture: SpeechCapture?
    @State private var attempts = 0
    @State private var startedAt = Date()
    @State private var logged = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("第 \(index + 1) / \(targets.count) 個").font(.caption).foregroundStyle(.secondary)
                Text(focus).font(.subheadline)
                if targets.indices.contains(index) {
                    let target = targets[index]
                    HStack {
                        Text(target).font(.system(size: 44, weight: .semibold))
                        Spacer()
                        SpeakButton(text: target, slow: true)
                        SpeakButton(text: target)
                    }
                    if let check {
                        PronunciationCheckView(check: check, recordingURL: capture?.audioURL)
                        HStack {
                            Button("再試一次") {
                                self.check = nil
                                capture = nil
                            }
                            .buttonStyle(.bordered)
                            Spacer()
                            if index + 1 < targets.count {
                                Button("下一個") { move(to: index + 1) }.buttonStyle(.borderedProminent)
                            } else {
                                Button("完成") { finishSession() }.buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        SpeechRecorderControl { result in
                            evaluate(target: target, result)
                        }
                        .id("\(index)-\(attempts)")
                        if index + 1 < targets.count {
                            Button("跳過") { move(to: index + 1) }.font(.caption).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                if logged {
                    Label("已完成本組練習", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startedAt = Date()
            if let first = targets.first { Speaker.shared.speak(first) }
        }
    }

    private func evaluate(target: String, _ result: SpeechCapture) {
        let c = SpeechComparison.check(target: target, transcripts: result.transcripts)
        capture = result
        check = c
        attempts += 1
        store.recordPronunciation(target: target, capture: result, check: c, activity: .minimalPairs)
    }

    private func move(to i: Int) {
        index = i
        check = nil
        capture = nil
        Speaker.shared.speak(targets[i])
    }

    private func finishSession() {
        guard !logged else { return }
        logged = true
        store.logActivity(.minimalPairs, seconds: Date().timeIntervalSince(startedAt))
    }
}

/// 快速反應：看中文，3 秒內開口說出韓語
struct RapidResponseView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var count = 10
    /// 開口時限（秒）
    let limit: Double = 3

    @State private var words: [VocabularyItem] = []
    @State private var index = 0
    @State private var shownAt = Date()
    @State private var startedAt = Date()
    @State private var grade: DrillGrade?
    @State private var correct = 0
    @State private var finished = false
    @State private var loaded = false
    @State private var retryNote: String?

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if words.isEmpty {
                ContentUnavailableView("還沒有可以練習的單字", systemImage: "bolt.slash",
                                       description: Text("先學一些新單字，快速反應會從你學過的單字出題。"))
            } else if finished {
                VStack {
                    SessionSummaryView(title: "快速反應完成", correct: correct, total: words.count,
                                       note: "只有答對而且 \(Int(limit)) 秒內開口才算通過。")
                    Button("返回") { dismiss() }.buttonStyle(.borderedProminent)
                }
            } else {
                itemView(words[index])
            }
        }
        .navigationTitle("快速反應")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let introduced = Set(store.cards().map(\.vocabularyID))
            var pool = store.library.allVocabulary.filter { introduced.contains($0.id) }
            if pool.count < 5 { pool = store.currentLesson?.vocabulary ?? [] }
            var rng = SeededGenerator(seed: SeededGenerator.seed("rapid-\(Date().timeIntervalSince1970)"))
            words = Array(pool.shuffled(using: &rng).prefix(count))
            startedAt = Date()
            shownAt = Date()
        }
    }

    private func itemView(_ word: VocabularyItem) -> some View {
        VStack(spacing: 20) {
            Text("第 \(index + 1) / \(words.count) 題・\(Int(limit)) 秒內開口").font(.caption).foregroundStyle(.secondary)
            Text(word.chinese).font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center)
            if let grade {
                let pass = grade.verdict.isAcceptable && grade.withinTimeLimit
                FeedbackBanner(correct: pass, title: pass ? "通過" : (grade.verdict.isAcceptable ? "正確但太慢" : grade.verdict.title),
                               detail: "\(grade.feedback)\n開口時間 \(String(format: "%.1f", grade.responseSeconds)) 秒")
                KoreanLine(korean: word.korean, romanization: word.romanization, chinese: word.chinese)
                Button(index + 1 < words.count ? "下一題" : "完成") { advance() }
                    .buttonStyle(.borderedProminent)
            } else {
                SpeechRecorderControl(autoStart: true) { capture in
                    evaluate(word, capture)
                }
                .id(index)
                if let retryNote {
                    Text(retryNote).font(.caption).foregroundStyle(.orange)
                }
                Text("這個練習需要語音；用鍵盤無法在 3 秒內作答，所以不提供鍵盤模式。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }

    private func evaluate(_ word: VocabularyItem, _ capture: SpeechCapture) {
        guard !capture.transcripts.isEmpty else {
            retryNote = "沒有辨識到語音，請再按一次麥克風。"
            return
        }
        retryNote = nil
        let seconds = (capture.onsetDate ?? capture.stoppedAt).timeIntervalSince(shownAt)
        let g = SpeechAnswerGrader.grade(transcripts: capture.transcripts, answers: [word.korean],
                                         responseSeconds: seconds, timeLimit: limit)
        grade = g
        let pass = g.verdict.isAcceptable && g.withinTimeLimit
        if pass { correct += 1 }
        store.recordAttempt(skill: .speaking, activity: .rapidResponse, sourceID: word.id, correct: pass, responseSeconds: seconds)
        Speaker.shared.speak(word.korean)
    }

    private func advance() {
        if index + 1 < words.count {
            index += 1
            grade = nil
            retryNote = nil
            shownAt = Date()
        } else {
            finished = true
            store.logActivity(.rapidResponse, seconds: Date().timeIntervalSince(startedAt))
        }
    }
}

/// 聽力中心：各課聽力練習與聽音辨識
struct ListeningHomeView: View {
    @Environment(StudyStore.self) private var store

    var body: some View {
        List {
            Section("聽音辨識") {
                NavigationLink { DiscriminationView(mode: .sounds) } label: {
                    Label("聽音選字", systemImage: "waveform")
                }
                NavigationLink { DiscriminationView(mode: .minimalPairs) } label: {
                    Label("最小對立音", systemImage: "arrow.left.arrow.right")
                }
            }
            Section("課程聽力") {
                ForEach(Array(store.lessonsUpToCurrent.reversed())) { lesson in
                    NavigationLink { ListeningPracticeView(lesson: lesson) } label: {
                        LabeledContent(lesson.title, value: "\(lesson.listening.count) 題")
                    }
                }
            }
            Section {
                Text("音檔由 iOS 韓語合成語音朗讀，不是真人錄音。").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("聽力")
    }
}
