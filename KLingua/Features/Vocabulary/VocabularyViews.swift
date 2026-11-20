import SwiftUI
import KLinguaCore

/// 新單字：依 S → A → B → C 頻率與目前課程挑選，建立四面向單字卡
struct NewWordsView: View {
    @Environment(StudyStore.self) private var store
    var count = 8

    @State private var words: [VocabularyItem] = []
    @State private var loaded = false
    @State private var index = 0
    @State private var startedAt = Date()
    @State private var logged = false

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if words.isEmpty {
                ContentUnavailableView("今天沒有新單字", systemImage: "tray",
                                       description: Text("可能原因：目前已開放課程的單字都學過了，或第一格待複習的單字超過 40 個（先複習再學新字，避免越積越多）。"))
            } else {
                TabView(selection: $index) {
                    ForEach(Array(words.enumerated()), id: \.element.id) { i, word in
                        ScrollView { WordDetailCard(word: word).padding() }
                            .tag(i)
                    }
                    finishPage.tag(words.count)
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .onChange(of: index) { _, i in
                    if i < words.count { Speaker.shared.speak(words[i].korean) }
                }
            }
        }
        .navigationTitle("新單字")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            words = store.introduceNewWords(count: count)
            loaded = true
            startedAt = Date()
            if let first = words.first { Speaker.shared.speak(first.korean) }
        }
    }

    private var finishPage: some View {
        VStack(spacing: 16) {
            Text("已加入 \(words.count) 個單字到單字卡").font(.title3.bold())
            Text("每個單字分成「中文理解、韓文辨識、聽力辨識、口語輸出」四個面向，各自排程複習。").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            NavigationLink {
                ReviewSessionView()
            } label: {
                Label("馬上複習", systemImage: "rectangle.stack.fill").font(.headline)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .onAppear {
            guard !logged else { return }
            logged = true
            store.logActivity(.newVocabulary, seconds: Date().timeIntervalSince(startedAt), newWords: words.count)
        }
    }
}

/// 單字完整資訊
struct WordDetailCard: View {
    let word: VocabularyItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(word.tier.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
                Text(word.partOfSpeech.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                SpeakButton(text: word.korean, slow: true)
            }
            KoreanLine(korean: word.korean, romanization: word.romanization, pronunciation: word.pronunciation,
                       chinese: word.chinese, font: .system(size: 40, weight: .semibold))
            GroupBox("例句") {
                KoreanLine(korean: word.example.korean, chinese: word.example.chinese, font: .body)
            }
            GroupBox("用法") {
                Text(word.usage).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let mistake = word.commonMistake {
                GroupBox("常見錯誤") {
                    Text(mistake).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

extension PartOfSpeech {
    var title: String {
        switch self {
        case .noun: "名詞"
        case .pronoun: "代名詞"
        case .verb: "動詞"
        case .adjective: "形容詞"
        case .adverb: "副詞"
        case .numeral: "數詞"
        case .particle: "助詞"
        case .expression: "常用語"
        case .interjection: "感嘆詞"
        case .counter: "量詞"
        }
    }
}

/// 單字庫（含 SRS 狀態）
struct VocabularyLibraryView: View {
    @Environment(StudyStore.self) private var store
    @State private var search = ""
    @State private var tier: VocabularyTier?

    var body: some View {
        let _ = store.revision
        let cards = store.cardsByVocabulary()
        let words = store.availableLessons.flatMap(\.vocabulary).filter { w in
            (tier == nil || w.tier == tier) &&
            (search.isEmpty || w.korean.contains(search) || w.chinese.contains(search))
        }
        let due = store.dueSchedules().count
        List {
            Section {
                NavigationLink {
                    SRSOverviewView()
                } label: {
                    LabeledContent("SRS 複習中心", value: due > 0 ? "\(due) 個到期" : "沒有到期")
                }
            }
            Section {
                Picker("頻率", selection: $tier) {
                    Text("全部").tag(VocabularyTier?.none)
                    ForEach(VocabularyTier.allCases) { t in
                        Text(t.rawValue).tag(Optional(t))
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("\(words.count) 個單字・已加入單字卡 \(cards.count) 個") {
                ForEach(words) { word in
                    NavigationLink {
                        VocabularyDetailView(word: word)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(word.korean).font(.headline)
                                Text(word.chinese).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let card = cards[word.id] {
                                Text(lowestBox(card).shortTitle).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("未學").font(.caption).foregroundStyle(.tertiary)
                            }
                            Text(word.tier.rawValue).font(.caption.bold()).foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜尋韓文或中文")
        .navigationTitle("單字庫")
    }

    private func lowestBox(_ card: Flashcard) -> LeitnerBox {
        (card.facets ?? []).compactMap { LeitnerBox(rawValue: $0.boxRaw) }.min() ?? .box1
    }
}

struct VocabularyDetailView: View {
    @Environment(StudyStore.self) private var store
    let word: VocabularyItem

    var body: some View {
        let _ = store.revision
        let card = store.cardsByVocabulary()[word.id]
        List {
            Section { WordDetailCard(word: word) }
            Section {
                if let card {
                    ForEach((card.facets ?? []).sorted { $0.facetRaw < $1.facetRaw }) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(f.facet.title)
                                Spacer()
                                Text((LeitnerBox(rawValue: f.boxRaw) ?? .box1).shortTitle).foregroundStyle(.secondary)
                            }
                            Text(facetDetail(f)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Button("加入單字卡") { store.addCards(for: [word]) }
                }
            } header: {
                Text("記憶狀態（四個面向分開計算）")
            }
        }
        .navigationTitle(word.korean)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func facetDetail(_ f: FacetSchedule) -> String {
        var parts = ["下次 \(f.nextDue.formatted(date: .abbreviated, time: .omitted))"]
        if f.reviewCount > 0 {
            parts.append("答對 \(f.correctCount)/\(f.reviewCount)")
        } else {
            parts.append("尚未複習")
        }
        if let avg = f.averageResponseSeconds {
            parts.append("平均反應 \(String(format: "%.1f", avg)) 秒")
        }
        if f.lapses > 0 { parts.append("遺忘 \(f.lapses) 次") }
        return parts.joined(separator: "・")
    }
}

/// SRS 複習中心：五個箱子的分布與到期數
struct SRSOverviewView: View {
    @Environment(StudyStore.self) private var store
    @State private var facet: CardFacet?

    var body: some View {
        let _ = store.revision
        let counts = store.boxCounts(facet: facet)
        let total = counts.values.reduce(0, +)
        let due = store.dueSchedules().count
        List {
            Section {
                NavigationLink {
                    ReviewSessionView()
                } label: {
                    Label(due > 0 ? "開始複習（\(due) 個到期）" : "目前沒有到期的複習", systemImage: "rectangle.stack.fill")
                }
                .disabled(due == 0)
                NavigationLink {
                    NewWordsView()
                } label: {
                    Label("學新單字", systemImage: "plus.rectangle.on.rectangle")
                }
            }
            Section {
                Picker("面向", selection: $facet) {
                    Text("全部").tag(CardFacet?.none)
                    ForEach(CardFacet.allCases) { f in Text(f.title).tag(Optional(f)) }
                }
                ForEach(LeitnerBox.allCases, id: \.self) { box in
                    let n = counts[box] ?? 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(box.title)
                            Spacer()
                            Text("\(n)").monospacedDigit()
                        }
                        ProgressView(value: Double(n), total: Double(max(1, total)))
                    }
                }
            } header: {
                Text("五格分布（共 \(total) 個面向）")
            } footer: {
                Text("答對且反應快 → 升一格；答對但慢 → 留在原格、縮短間隔；部分正確或混淆 → 降一格；忘記 → 回第一格。基本間隔 1／3／7／30／90 天，會依你的表現自動調整。")
            }
        }
        .navigationTitle("SRS 複習中心")
    }
}
