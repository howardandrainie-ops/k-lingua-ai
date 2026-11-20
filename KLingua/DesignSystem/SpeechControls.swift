import SwiftUI
import KLinguaCore

/// 麥克風按鈕：處理權限、錄音中音量、即時辨識文字、自動停止
struct SpeechRecorderControl: View {
    var autoStart = false
    let onResult: (SpeechCapture) -> Void

    @State private var errorText: String?
    @State private var delivering = false

    var body: some View {
        let speech = SpeechInput.shared
        VStack(spacing: 10) {
            switch speech.permission {
            case .unavailable:
                Label("這台裝置無法使用韓語語音辨識。", systemImage: "mic.slash").foregroundStyle(.secondary)
            case .denied:
                VStack(spacing: 6) {
                    Label("麥克風或語音辨識權限已關閉。", systemImage: "mic.slash").foregroundStyle(.orange)
                    Button("到「設定」開啟權限") { openAppSettings() }
                }
            case .notDetermined:
                Button {
                    Task { await speech.requestPermissions() }
                } label: {
                    Label("允許使用麥克風與語音辨識", systemImage: "mic.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            case .granted:
                recorder(speech)
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            if autoStart && speech.permission == .granted { begin() }
        }
        .onDisappear {
            SpeechInput.shared.cancel()
        }
    }

    @ViewBuilder
    private func recorder(_ speech: SpeechInput) -> some View {
        switch speech.phase {
        case .idle:
            Button {
                begin()
            } label: {
                Image(systemName: "mic.circle.fill").font(.system(size: 64))
            }
            .accessibilityLabel("開始說話")
            Text("按下麥克風後說韓語，說完會自動停止").font(.caption).foregroundStyle(.secondary)
        case .listening:
            Button {
                finish()
            } label: {
                Image(systemName: "stop.circle.fill").font(.system(size: 64)).foregroundStyle(.red)
            }
            .accessibilityLabel("停止")
            LevelMeter(level: speech.level)
            Text(speech.partial.isEmpty ? (speech.onsetDate == nil ? "聆聽中…" : "辨識中…") : speech.partial)
                .font(.title3)
                .lineLimit(2)
        case .processing:
            ProgressView("辨識中…")
        }
        Text(speech.supportsOnDevice ? "裝置端辨識（錄音不會上傳）" : "需要網路：語音會傳送到 Apple 伺服器辨識")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func begin() {
        errorText = nil
        delivering = false
        do {
            try SpeechInput.shared.start(onAutoStop: { finish() })
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func finish() {
        guard !delivering else { return }
        delivering = true
        Task {
            let capture = await SpeechInput.shared.stop()
            if let message = capture.errorMessage { errorText = message }
            onResult(capture)
        }
    }
}

struct LevelMeter: View {
    let level: Float

    var body: some View {
        // -60 dB → 0, -10 dB → 1
        let value = Double(max(0, min(1, (level + 60) / 50)))
        ProgressView(value: value)
            .tint(value > 0.3 ? Color.green : Color.gray)
            .frame(maxWidth: 200)
            .animation(.linear(duration: 0.1), value: value)
    }
}

/// 作答輸入：語音或鍵盤（依設定預設，可隨時切換）
struct AnswerInputView: View {
    @Environment(StudyStore.self) private var store
    var allowsSpeech = true
    var autoStartSpeech = false
    var placeholder = "用韓文回答"
    var onFirstKey: (Date) -> Void = { _ in }
    let onText: (String) -> Void
    let onSpeech: (SpeechCapture) -> Void

    @State private var typed = ""
    @State private var keyboardOverride: Bool?
    @FocusState private var focused: Bool

    private var speechMode: Bool {
        guard allowsSpeech else { return false }
        if let keyboardOverride { return !keyboardOverride }
        return store.profile().preferSpeechInput && SpeechInput.shared.permission != .unavailable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if speechMode {
                SpeechRecorderControl(autoStart: autoStartSpeech, onResult: onSpeech)
                Button("改用鍵盤") { keyboardOverride = true }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            } else {
                TextField(placeholder, text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .onChange(of: typed) { old, new in
                        if old.isEmpty && !new.isEmpty { onFirstKey(Date()) }
                    }
                HStack {
                    Button("送出", action: submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                    if allowsSpeech {
                        Button("改用語音") { keyboardOverride = false }.font(.caption)
                    }
                }
                .onAppear { focused = true }
            }
        }
    }

    private func submit() {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        focused = false
        onText(t)
    }
}

/// 發音比對結果（必附限制說明）
struct PronunciationCheckView: View {
    let check: PronunciationCheck
    var recordingURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(check.verdict.title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)
            if !check.heard.isEmpty {
                Text("辨識器聽到：「\(check.heard)」").font(.title3)
                Text("語音辨識吻合度 \(check.matchRatio.formatted(.percent.precision(.fractionLength(0))))（不是發音分數）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(check.differences.enumerated()), id: \.offset) { _, d in
                VStack(alignment: .leading, spacing: 2) {
                    switch d.kind {
                    case .substituted: Text("「\(d.expected)」→「\(d.heard)」").bold()
                    case .missing: Text("缺少「\(d.expected)」").bold()
                    case .extra: Text("多出「\(d.heard)」").bold()
                    }
                    if let hint = d.hint { Text(hint).font(.subheadline) }
                }
            }
            ForEach(check.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button { Speaker.shared.speak(check.target) } label: { Label("示範音", systemImage: "speaker.wave.2.fill") }
                if let recordingURL {
                    Button { RecordingPlayer.shared.play(recordingURL) } label: { Label("我的錄音", systemImage: "person.wave.2.fill") }
                }
            }
            .buttonStyle(.bordered)
            DisclosureGroup("這個比對能判斷什麼？") {
                Text(SpeechComparison.limitations).font(.caption).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var icon: String {
        switch check.verdict {
        case .recognizedAsTarget: "checkmark.circle.fill"
        case .closeMatch: "circle.lefthalf.filled"
        case .different: "xmark.circle.fill"
        case .nothingRecognized: "mic.slash"
        }
    }

    private var color: Color {
        switch check.verdict {
        case .recognizedAsTarget: .green
        case .closeMatch: .orange
        case .different: .red
        case .nothingRecognized: .gray
        }
    }
}
