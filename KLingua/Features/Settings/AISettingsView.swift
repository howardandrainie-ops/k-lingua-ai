import SwiftUI
import KLinguaCore

/// AI／API 設定：選擇服務、模型、輸入 API Key（只存 Keychain）、測試連線
struct AISettingsView: View {
    @Environment(StudyStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var provider: AIProvider?
    @State private var model = ""
    @State private var keyInput = ""
    @State private var loaded = false
    @State private var message: (ok: Bool, text: String)?
    @State private var testing = false

    var body: some View {
        let _ = store.revision
        let savedKey = provider.flatMap { KeychainStore.read(account: $0.rawValue) }
        Form {
            Section {
                Picker("AI 服務", selection: $provider) {
                    Text("不使用 AI").tag(AIProvider?.none)
                    ForEach(AIProvider.allCases) { p in Text(p.title).tag(Optional(p)) }
                }
                .onChange(of: provider) { _, p in
                    if loaded { model = p?.defaultModel ?? "" }
                    keyInput = ""
                    message = nil
                }
            } footer: {
                Text("不使用 AI 時，課程、單字卡、SRS、發音與離線情境練習都能正常使用。")
            }

            if let provider {
                Section {
                    TextField("模型名稱", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    Button("使用預設：\(provider.defaultModel)") { model = provider.defaultModel }
                        .font(.caption)
                } header: {
                    Text("模型")
                } footer: {
                    Text("各家模型名稱會更新；若測試連線顯示找不到模型，請依服務商的文件修改。")
                }

                Section {
                    if let savedKey {
                        LabeledContent("已儲存的金鑰", value: KeychainStore.masked(savedKey))
                    }
                    SecureField(savedKey == nil ? provider.keyPlaceholder : "輸入新金鑰以取代", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("取得 API Key") { openURL(provider.consoleURL) }
                    if savedKey != nil {
                        Button("刪除這個金鑰", role: .destructive) {
                            store.deleteAIKey(for: provider)
                            message = (true, "已從鑰匙圈刪除。")
                        }
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("金鑰只存在這台 iPhone 的鑰匙圈（Keychain），不會同步到 iCloud、不會寫入資料庫或檔案。使用費用由你的帳戶支付。")
                }
            }

            Section {
                Button("儲存") { saveSettings() }
                    .disabled(provider != nil && savedKey == nil && keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if provider != nil {
                    Button {
                        Task { await test() }
                    } label: {
                        if testing { ProgressView() } else { Text("儲存並測試連線") }
                    }
                    .disabled(testing || (savedKey == nil && keyInput.trimmingCharacters(in: .whitespaces).isEmpty))
                }
                if let message {
                    Label(message.text, systemImage: message.ok ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(message.ok ? Color.green : Color.red)
                        .font(.footnote)
                }
            }

            Section("會傳送哪些內容") {
                Text("只會傳送：情境設定、你在對話中說或輸入的韓語句子、對話紀錄，以及你學過的單字清單（用來控制難度）。不會傳送姓名、帳號或其他個人資料。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI 設定")
        .onAppear {
            guard !loaded else { return }
            provider = store.aiProvider
            model = store.aiModel
            DispatchQueue.main.async { loaded = true }
        }
    }

    @discardableResult
    private func saveSettings() -> Bool {
        do {
            try store.setAI(provider: provider, model: model, key: keyInput.isEmpty ? nil : keyInput)
            keyInput = ""
            message = (true, provider == nil ? "已關閉 AI 功能。" : "已儲存。")
            return true
        } catch {
            message = (false, error.localizedDescription)
            return false
        }
    }

    private func test() async {
        guard saveSettings(), let client = store.aiClient() else {
            if message?.ok != false { message = (false, "沒有可用的 API Key。") }
            return
        }
        testing = true
        defer { testing = false }
        do {
            let reply = try await client.complete(AIRequest(system: "You are a connection test. Reply with the single Korean word 안녕하세요.",
                                                            messages: [AIChatMessage(role: .user, text: "test")], maxTokens: 2000))
            message = (true, "連線成功：\(reply.prefix(40))")
        } catch let e as AIServiceError {
            message = (false, e.userMessage)
        } catch {
            message = (false, error.localizedDescription)
        }
    }
}
