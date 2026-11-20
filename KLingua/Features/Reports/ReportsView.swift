import SwiftUI
import SwiftData
import KLinguaCore

/// 能力報告：雷達圖（最近 90 天）＋本週／上週週報。所有數字來自實際作答紀錄。
struct ReportsView: View {
    @Environment(StudyStore.self) private var store
    @State private var weekOffset = 0

    var body: some View {
        let _ = store.revision
        let estimates = store.skillEstimates()
        let thisWeek = WeeklyReportBuilder.weekStart(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -7 * weekOffset, to: thisWeek) ?? thisWeek
        let report = store.weeklyReport(weekStart: start)
        List {
            Section {
                RadarChartView(points: estimates.map { RadarChartView.Point(label: $0.skill.title, value: $0.score) })
                    .frame(height: 300)
                    .accessibilityLabel("能力雷達圖")
            } header: {
                Text("能力雷達圖（最近 90 天）")
            } footer: {
                Text("每項能力至少 \(SkillEstimator.minimumAttempts) 題才畫出分數；灰色標籤表示資料不足（顯示為 0，不代表能力為 0）。分數 = (答對+1)/(作答+2)，避免題數少時出現 0% 或 100%。")
            }

            Section {
                Picker("週", selection: $weekOffset) {
                    Text("本週").tag(0)
                    Text("上週").tag(1)
                }
                .pickerStyle(.segmented)
                LabeledContent("期間", value: weekRange(start))
                LabeledContent("練習時間", value: "\(report.studyMinutes) 分鐘・\(report.activeDays) 天")
                LabeledContent("新單字／複習", value: "\(report.newWords) ／ \(report.reviews)")
                LabeledContent("作答題數", value: "\(report.attempts)")
                LabeledContent("整體答對率", value: report.accuracy.map(percent) ?? "題數不足")
            } header: {
                Text("週報")
            }

            Section("各項能力（本週 vs 上週）") {
                ForEach(report.skills.filter { $0.attempts > 0 || $0.previousAccuracy != nil }, id: \.skill) { line in
                    HStack {
                        Text(line.skill.title)
                        Spacer()
                        Text(line.accuracy.map(percent) ?? "\(line.attempts) 題（不足）")
                            .foregroundStyle(line.accuracy == nil ? Color.secondary : Color.primary)
                        if let now = line.accuracy, let before = line.previousAccuracy {
                            let diff = Int(((now - before) * 100).rounded())
                            Text(diff >= 0 ? "▲\(diff)" : "▼\(-diff)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(diff >= 0 ? Color.green : Color.red)
                        }
                    }
                }
                if report.attempts == 0 {
                    Text("這週沒有作答紀錄。").foregroundStyle(.secondary)
                }
            }

            if !report.topMistakes.isEmpty {
                Section("最常見的錯誤") {
                    ForEach(report.topMistakes, id: \.category) { m in
                        LabeledContent((DrillVerdict(rawValue: m.category) ?? .incorrect).title, value: "\(m.count) 次")
                    }
                }
            }

            Section("建議") {
                ForEach(report.suggestions, id: \.self) { Text($0) }
            }
        }
        .navigationTitle("能力報告")
        .onAppear { store.saveWeeklySnapshotIfNeeded() }
    }

    private func percent(_ v: Double) -> String { v.formatted(.percent.precision(.fractionLength(0))) }

    private func weekRange(_ start: Date) -> String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(start.formatted(.dateTime.month().day()))–\(end.formatted(.dateTime.month().day()))"
    }
}

/// 雷達圖（不依賴第三方套件）
struct RadarChartView: View {
    struct Point {
        var label: String
        /// 0–1；資料不足時為 nil
        var value: Double?
    }

    let points: [Point]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2 - 36
            ZStack {
                ForEach(1...4, id: \.self) { ring in
                    polygon(values: Array(repeating: Double(ring) / 4, count: points.count), center: center, radius: radius)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
                ForEach(points.indices, id: \.self) { i in
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: point(i, value: 1, center: center, radius: radius))
                    }
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                }
                let values = points.map { $0.value ?? 0 }
                polygon(values: values, center: center, radius: radius)
                    .fill(Color.accentColor.opacity(0.25))
                polygon(values: values, center: center, radius: radius)
                    .stroke(Color.accentColor, lineWidth: 2)
                ForEach(points.indices, id: \.self) { i in
                    let pos = point(i, value: 1.22, center: center, radius: radius)
                    VStack(spacing: 0) {
                        Text(points[i].label).font(.caption2)
                        Text(points[i].value.map { "\(Int(($0 * 100).rounded()))%" } ?? "不足")
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(points[i].value == nil ? Color.secondary : Color.primary)
                    .position(pos)
                }
            }
        }
    }

    private func point(_ i: Int, value: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(max(1, points.count))
        return CGPoint(x: center.x + CGFloat(cos(angle) * value) * radius,
                       y: center.y + CGFloat(sin(angle) * value) * radius)
    }

    private func polygon(values: [Double], center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            for (i, v) in values.enumerated() {
                let pt = point(i, value: max(0, min(1, v)), center: center, radius: radius)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }
}
