import SwiftUI
import KLinguaCore

/// 播放按鈕（一般速度／慢速）
struct SpeakButton: View {
    let text: String
    var slow = false

    var body: some View {
        Button {
            Speaker.shared.speak(text, slow: slow)
        } label: {
            Image(systemName: slow ? "tortoise.fill" : "speaker.wave.2.fill")
                .imageScale(.large)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(slow ? "慢速播放" : "播放")
    }
}

/// 一行韓文：韓文、（依設定）羅馬拼音、實際發音、中文，右側播放鍵
struct KoreanLine: View {
    @Environment(StudyStore.self) private var store
    let korean: String
    var romanization: String? = nil
    var pronunciation: String? = nil
    var chinese: String? = nil
    var font: Font = .title3

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(korean).font(font)
                if store.profile().showRomanization, let romanization {
                    Text(romanization).font(.caption).foregroundStyle(.secondary)
                }
                if let pronunciation {
                    Text("實際發音 \(pronunciation)").font(.caption).foregroundStyle(.orange)
                }
                if let chinese {
                    Text(chinese).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            SpeakButton(text: korean)
        }
    }
}

/// 作答回饋
struct FeedbackBanner: View {
    let correct: Bool
    let title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(correct ? .green : .red)
            if let detail, !detail.isEmpty {
                Text(detail).font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background((correct ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// 練習結束畫面
struct SessionSummaryView: View {
    let title: String
    let correct: Int
    let total: Int
    var note: String? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.checkered").font(.system(size: 44)).foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            if total > 0 {
                Text("答對 \(correct) / \(total)（\(QuizScoring.ratio(correct: correct, total: total), format: .percent.precision(.fractionLength(0)))）")
                    .font(.title3)
            } else {
                Text("沒有計分的題目").foregroundStyle(.secondary)
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

/// 尚未實作的功能：明確標示在哪個階段完成，不放假畫面
struct NotYetAvailableView: View {
    let title: String
    let reason: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "hammer")
        } description: {
            Text(reason)
        }
    }
}

extension DrillVerdict {
    var title: String {
        switch self {
        case .correct: "正確"
        case .correctWithMinorDifference: "正確（小差異）"
        case .particleError: "助詞錯誤"
        case .spellingError: "拼字錯誤"
        case .incorrect: "錯誤"
        }
    }
}

extension LeitnerBox {
    var shortTitle: String { "第 \(rawValue) 格" }
}

func formatMinutes(_ seconds: Double) -> String {
    let m = Int((seconds / 60).rounded())
    return "\(m) 分鐘"
}
