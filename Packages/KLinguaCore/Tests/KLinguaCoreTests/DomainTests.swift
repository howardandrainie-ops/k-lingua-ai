import Testing
@testable import KLinguaCore

@Suite("領域型別")
struct DomainTests {
    @Test("五格預設複習間隔為 1/3/7/30/90 天")
    func leitnerDefaultIntervals() {
        #expect(LeitnerBox.allCases.map(\.defaultIntervalDays) == [1, 3, 7, 30, 90])
    }

    @Test("格位升降邊界")
    func leitnerNavigation() {
        #expect(LeitnerBox.box1.previous == nil)
        #expect(LeitnerBox.box1.next == .box2)
        #expect(LeitnerBox.box5.next == nil)
        #expect(LeitnerBox.box5.previous == .box4)
    }

    @Test("詞彙分級排序 S < A < B < C")
    func tierOrdering() {
        #expect([VocabularyTier.c, .s, .b, .a].sorted() == [.s, .a, .b, .c])
    }

    @Test("課程共八階段，依序編號")
    func curriculumStages() {
        #expect(CurriculumStage.allCases.count == 8)
        #expect(CurriculumStage.allCases.map(\.rawValue) == Array(1...8))
    }

    @Test("每張卡追蹤四個面向")
    func cardFacets() {
        #expect(CardFacet.allCases.count == 4)
    }
}
