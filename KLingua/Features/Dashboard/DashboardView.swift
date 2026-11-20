import SwiftUI
import KLinguaCore

struct DashboardView: View {
    @Environment(StudyStore.self) private var store

    var body: some View {
        let _ = store.revision
        let now = Date()
        let profile = store.profile()
        let plan = store.todayPlan(at: now)
        let done = store.completedToday(at: now)
        let record = store.todayRecord(at: now)
        let due = store.dueSchedules(at: now).count
        let mistakes = store.openMistakes().count
        let lessons = store.availableLessons
        let finished = lessons.filter { lesson in
            let s = store.status(of: lesson)
            return s == .completed || s == .skippedByTest
        }.count
        let estimates = store.skillEstimates(at: now)

        List {
            Section("今天") {
                LabeledContent("每日目標", value: "\(profile.dailyMinutes) 分鐘")
                LabeledContent("今日已練習", value: formatMinutes(record?.studiedSeconds ?? 0))
                LabeledContent("今日課表", value: "\(plan.filter { done.contains($0.activity) }.count) / \(plan.count) 項完成")
                if let record, record.newWords + record.reviews > 0 {
                    LabeledContent("新單字／複習", value: "\(record.newWords) ／ \(record.reviews)")
                }
            }

            Section("目前課程") {
                if let lesson = store.currentLesson {
                    NavigationLink {
                        LessonView(lesson: lesson)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let unit = store.library.unit(containing: lesson.id) {
                                Text("第 \(unit.number) 單元・\(unit.title)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(lesson.title).font(.headline)
                        }
                    }
                }
                LabeledContent("已完成課程", value: "\(finished) / \(lessons.count)（已開放）")
            }

            Section("單字卡") {
                if due > 0 {
                    NavigationLink {
                        ReviewSessionView()
                    } label: {
                        LabeledContent("到期複習", value: "\(due) 個")
                    }
                } else {
                    LabeledContent("到期複習", value: "沒有")
                }
                LabeledContent("已學單字", value: "\(store.cards().count)")
            }

            Section("練習中心") {
                NavigationLink { PronunciationHomeView() } label: { Label("發音練習", systemImage: "mic") }
                NavigationLink { ListeningHomeView() } label: { Label("聽力", systemImage: "ear") }
                NavigationLink { RapidResponseView() } label: { Label("快速反應", systemImage: "bolt") }
                NavigationLink { ScenariosView() } label: {
                    LabeledContent {
                        Text(store.aiAvailable ? "" : "需要 AI 設定")
                    } label: {
                        Label("AI 情境對話（15 個場景）", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            }

            if mistakes > 0 {
                Section {
                    NavigationLink {
                        MistakesView()
                    } label: {
                        LabeledContent("待複習錯誤", value: "\(mistakes) 個")
                    }
                }
            }

            Section {
                ForEach(estimates, id: \.skill) { SkillRow(estimate: $0) }
            } header: {
                Text("能力概況")
            } footer: {
                Text("依最近 90 天的實際作答計算（含診斷測驗）。同一能力少於 \(SkillEstimator.minimumAttempts) 題時不顯示分數，避免沒有根據的百分比。")
            }
        }
        .navigationTitle("K-LINGUA")
    }
}

struct SkillRow: View {
    let estimate: SkillEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(estimate.skill.title)
                Spacer()
                if let score = estimate.score {
                    Text(score.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                } else {
                    Text("資料不足（\(estimate.attempts)/\(SkillEstimator.minimumAttempts) 題）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let score = estimate.score {
                ProgressView(value: score)
                    .tint(score < PlacementEngine.weakThreshold ? Color.red : Color.green)
                Text("答對 \(estimate.correct)/\(estimate.attempts)・可信度\(confidence)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var confidence: String {
        switch estimate.confidence {
        case .insufficient: "不足"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}
