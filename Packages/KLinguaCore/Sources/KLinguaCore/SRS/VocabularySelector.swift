import Foundation

/// 新單字挑選：只從已開放課程中挑；依「目前課程 → 詞彙分級 S→C → 頻率排名」排序。
public enum VocabularySelector {
    /// 第一格待學量過多時，暫停引入新字（避免一天塞 100 個單字）
    public static let maxBox1Backlog = 40

    public static func nextNewWords(
        library: ContentLibrary,
        introducedIDs: Set<String>,
        currentLessonID: String?,
        box1Count: Int,
        count: Int
    ) -> [VocabularyItem] {
        guard count > 0, box1Count < maxBox1Backlog else { return [] }
        let allowed = min(count, maxBox1Backlog - box1Count)

        let lessons = library.allLessons
        guard !lessons.isEmpty else { return [] }
        let currentIndex = currentLessonID.flatMap { id in lessons.firstIndex { $0.id == id } } ?? 0
        // 只挑目前課程及之前的課程內容，避免出現還沒學過的字母或文法
        let eligible = lessons.prefix(through: min(currentIndex, lessons.count - 1))
            .enumerated()
            .flatMap { (lessonIndex, lesson) in lesson.vocabulary.map { (lessonIndex, $0) } }
            .filter { !introducedIDs.contains($0.1.id) }

        return eligible
            .sorted { a, b in
                if a.1.tier != b.1.tier { return a.1.tier < b.1.tier }
                if a.0 != b.0 { return a.0 < b.0 }
                return a.1.frequencyRank < b.1.frequencyRank
            }
            .prefix(allowed)
            .map(\.1)
    }
}
