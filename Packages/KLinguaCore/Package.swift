// swift-tools-version: 6.0
// KLinguaCore：與 UI 無關的純邏輯層（SRS、課程引擎、Drill 評分、能力評估）。
// 只依賴 Foundation，可在 macOS 上用 `swift test` 獨立測試，
// 亦可在安裝 Swift 工具鏈的 Windows / Linux 上測試。
import PackageDescription

let package = Package(
    name: "KLinguaCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KLinguaCore", targets: ["KLinguaCore"]),
    ],
    targets: [
        .target(name: "KLinguaCore", resources: [.process("Content")]),
        .testTarget(name: "KLinguaCoreTests", dependencies: ["KLinguaCore"]),
    ]
)
