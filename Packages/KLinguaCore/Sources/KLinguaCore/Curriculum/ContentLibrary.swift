import Foundation

public enum ContentError: Error, CustomStringConvertible {
    case missingResource(String)
    case decoding(String, Error)

    public var description: String {
        switch self {
        case .missingResource(let name): "找不到教材檔：\(name)"
        case .decoding(let name, let error): "教材檔 \(name) 格式錯誤：\(error)"
        }
    }
}

/// 從套件資源載入內建教材。
public struct ContentLibrary: Sendable {
    public let units: [CourseUnit]
    public let diagnostic: DiagnosticTest

    public init(units: [CourseUnit], diagnostic: DiagnosticTest) {
        self.units = units.sorted { $0.number < $1.number }
        self.diagnostic = diagnostic
    }

    /// 載入 Bundle.module 中的 units/*.json 與 diagnostic.json。
    public static func loadBundled() throws -> ContentLibrary {
        let unitFiles = (1...12).map { String(format: "unit%02d", $0) }
        var units: [CourseUnit] = []
        for name in unitFiles {
            units.append(try decode(CourseUnit.self, resource: name))
        }
        let diagnostic = try decode(DiagnosticTest.self, resource: "diagnostic")
        return ContentLibrary(units: units, diagnostic: diagnostic)
    }

    static func decode<T: Decodable>(_ type: T.Type, resource: String) throws -> T {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "json") else {
            throw ContentError.missingResource(resource + ".json")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ContentError.decoding(resource + ".json", error)
        }
    }

    public var allLessons: [Lesson] { units.flatMap(\.lessons) }

    public var allVocabulary: [VocabularyItem] { allLessons.flatMap(\.vocabulary) }

    public func lesson(id: String) -> Lesson? { allLessons.first { $0.id == id } }

    public func unit(containing lessonID: String) -> CourseUnit? {
        units.first { $0.lessons.contains { $0.id == lessonID } }
    }
}
