import SwiftUI
import KLinguaCore

/// 15 個 AI 情境
struct ScenariosView: View {
    @Environment(StudyStore.self) private var store

    var body: some View {
        let _ = store.revision
        List {
            if !store.aiAvailable {
                Section {
                    Label("尚未設定 AI 服務。設定 API Key 後才能和 AI 教練對話；不設定時可以用各課的「情境對話（離線腳本）」練習。",
                          systemImage: "info.circle")
                        .font(.footnote)
                    NavigationLink("前往 AI 設定") { AISettingsView() }
                }
            }
            ForEach(SpeechLevel.allCases) { level in
                Section(level.title) {
                    ForEach(ScenarioCatalog.all.filter { $0.speechLevel == level }) { scenario in
                        NavigationLink {
                            ConversationView(scenario: scenario)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scenario.title).font(.headline)
                                Text("你：\(scenario.learnerGoal)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!store.aiAvailable)
                    }
                }
            }
        }
        .navigationTitle("情境對話")
    }
}

/// 和 AI 教練的情境對話
struct ConversationView: View {
    @Environment(StudyStore.self) private var store
    let scenario: ConversationScenario

    @State private var session: ConversationSession?
    @State private var sending = false
    @State private var errorText: String?
    @State private var pendingText: String?
    @State private var startedAt = Date()
    @State private var turnCount = 0
    @State private var showGoal = true

    var body: some View {
        let _ = store.revision
        let messages = session.map { store.messages(of: $0) } ?? []
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if showGoal { goalCard }
                        ForEach(messages) { m in
                            MessageBubble(message: m).id(m.persistentModelID)
                        }
                        if sending {
                            HStack { ProgressView(); Text("AI 回覆中…").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let errorText {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(errorText).font(.footnote).foregroundStyle(.red)
                                if let pendingText {
                                    Button("重新傳送") { Task { await send(pendingText, retry: true) } }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            Divider()
            if !sending {
                AnswerInputView(placeholder: "用韓語回答（不會可以用中文問）",
                                onText: { text in Task { await send(text, retry: false) } },
                                onSpeech: { capture in
                                    if capture.transcripts.isEmpty {
                                        errorText = "沒有辨識到語音，請再說一次。"
                                    } else {
                                        Task { await send(capture.best, retry: false) }
                                    }
                                })
                    .id(messages.count)
                    .padding()
            }
        }
        .navigationTitle(scenario.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(showGoal ? "隱藏任務" : "任務") { showGoal.toggle() }
            }
        }
        .onAppear {
            guard session == nil else { return }
            session = store.startConversation(scenario)
            startedAt = Date()
            Speaker.shared.speak(scenario.opening)
        }
        .onDisappear {
            if turnCount > 0 {
                store.logActivity(.aiConversation, seconds: Date().timeIntervalSince(startedAt))
            }
        }
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("情境：\(scenario.setting)・對方：\(scenario.aiRole)").font(.subheadline)
            Text("你的任務：\(scenario.learnerGoal)").font(.subheadline.bold())
            Text("語體：\(scenario.speechLevel.title)").font(.caption).foregroundStyle(.secondary)
            Text("可以用的句子").font(.caption).foregroundStyle(.secondary)
            ForEach(scenario.keyPhrases, id: \.self) { p in
                KoreanLine(korean: p, font: .callout)
            }
            Text("AI 的修正與回覆可能有錯，僅供練習參考。").font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func send(_ raw: String, retry: Bool) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let session, !sending else { return }
        guard let client = store.aiClient() else {
            errorText = "尚未設定 AI 服務或 API Key。"
            return
        }
        // 先整理已完成的回合（只送韓語本文，不送修正與翻譯）
        let all = store.messages(of: session)
        var turns: [(user: String, reply: String)] = []
        var pendingUser: String?
        for m in all.dropFirst() { // 第一則是固定開場白
            if m.roleRaw == "user" {
                pendingUser = m.text
            } else if let u = pendingUser {
                turns.append((u, m.text))
                pendingUser = nil
            }
        }
        let userMessage: ConversationMessage
        if retry, let last = all.last, last.roleRaw == "user", last.text == text {
            userMessage = last
        } else {
            userMessage = store.appendMessage(to: session, role: "user", text: text)
        }

        let lessons = store.lessonsUpToCurrent
        let known = lessons.flatMap(\.vocabulary).map(\.korean)
        let level = "初級，目前學到「\(store.currentLesson?.title ?? "第一課")」"
        let request = AIRequest(system: CoachPrompt.system(scenario: scenario, learnerLevel: level, knownWords: known),
                                messages: CoachPrompt.history(opening: scenario.opening, turns: turns, latestUser: text),
                                maxTokens: 4000, wantsJSON: true)
        sending = true
        errorText = nil
        pendingText = text
        defer { sending = false }
        do {
            let raw = try await client.complete(request)
            let reply = CoachReplyParser.parse(raw)
            if let c = reply.correction {
                userMessage.correction = "\(c.corrected)\n\(c.explanation)"
            }
            let noteSuffix = reply.note.map { "\n💡 \($0)" } ?? ""
            store.appendMessage(to: session, role: "assistant", text: reply.reply,
                                translation: (reply.translation ?? "") + noteSuffix)
            store.recordConversationTurn(scenario: scenario, userText: text, correction: reply.correction)
            turnCount += 1
            pendingText = nil
            Speaker.shared.speak(reply.reply)
        } catch let e as AIServiceError {
            errorText = e.userMessage
        } catch {
            errorText = error.localizedDescription
        }
    }
}

struct MessageBubble: View {
    let message: ConversationMessage
    @State private var showTranslation = false

    var body: some View {
        let isUser = message.roleRaw == "user"
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(message.text).font(.body)
                    if !isUser { SpeakButton(text: message.text) }
                }
                if !isUser, let t = message.translation, !t.isEmpty {
                    if showTranslation {
                        Text(t).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("顯示翻譯") { showTranslation = true }.font(.caption)
                    }
                }
                if isUser, let c = message.correction {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("修正", systemImage: "pencil").font(.caption.bold()).foregroundStyle(.orange)
                        Text(c).font(.caption)
                        if let corrected = c.split(separator: "\n").first {
                            SpeakButton(text: String(corrected))
                        }
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14))
            if !isUser { Spacer(minLength: 40) }
        }
    }
}
