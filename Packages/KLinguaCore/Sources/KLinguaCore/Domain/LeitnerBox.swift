import Foundation

/// 五格記憶系統（Leitner System）的格位。
/// 預設間隔：1 / 3 / 7 / 30 / 90 天；實際間隔由 SRS 排程器依表現調整（第二階段實作）。
public enum LeitnerBox: Int, Codable, Sendable, CaseIterable, Comparable, Identifiable {
    case box1 = 1
    case box2
    case box3
    case box4
    case box5

    public var id: Int { rawValue }

    public var defaultIntervalDays: Int {
        switch self {
        case .box1: 1
        case .box2: 3
        case .box3: 7
        case .box4: 30
        case .box5: 90
        }
    }

    public var title: String {
        switch self {
        case .box1: "第一格・新學與每日密集"
        case .box2: "第二格・短期記憶"
        case .box3: "第三格・中期記憶"
        case .box4: "第四格・長期記憶"
        case .box5: "第五格・熟練記憶"
        }
    }

    public var next: LeitnerBox? { LeitnerBox(rawValue: rawValue + 1) }
    public var previous: LeitnerBox? { LeitnerBox(rawValue: rawValue - 1) }

    public static func < (lhs: LeitnerBox, rhs: LeitnerBox) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
