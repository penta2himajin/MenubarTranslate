// swift-tools-version:6.0
import PackageDescription

// MenubarTranslate — SwiftPM manifest. Toolchain pinned by ADR 0007.
//
// Layout keeps the repo's `src/` + `tests/` convention (AGENTS.md) so it composes with
// the oxidtr pipeline: `models/core.als` is the single source of truth; `src/Core/` is
// its generated Swift (plus the hand-written Support.swift), gated by `oxidtr check`.
// Hand-written logic lives in the sibling subdirectories of `src/` and shares one
// module with the generated types (they are internal). The generated `Core/Tests.swift`
// is XCTest-based scaffolding kept as a generation artifact but excluded from the
// build — the behavioural suite in `tests/` (swift-testing) covers the model's
// assertions and much more.
//
// Milestone 1 ships only the pure-logic core and the `mbt` console wrapper. The native
// engines (llama.cpp/Metal, MLX) land behind the `TranslationEngine` protocol in a
// later PR, in their own targets, so this core stays fast to build and portable.
let package = Package(
    name: "MenubarTranslate",
    platforms: [
        // mlx-swift (engine PR) requires macOS 14; rises to .v15 when the ADR-0006
        // Translation-framework fallback lands.
        .macOS(.v14)
    ],
    products: [
        .library(name: "MenubarTranslateCore", targets: ["MenubarTranslateCore"]),
        .library(name: "MTEngineLlama", targets: ["MTEngineLlama"]),
        .library(name: "MTEngineMLX", targets: ["MTEngineMLX"]),
        .executable(name: "mbt", targets: ["mbt"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MenubarTranslateCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "src",
            exclude: ["Core/Tests.swift", "EngineLlama", "EngineMLX"]
        ),
        .target(
            name: "MTEngineLlama",
            dependencies: ["MenubarTranslateCore"],
            path: "src/EngineLlama"
        ),
        .target(
            name: "MTEngineMLX",
            dependencies: ["MenubarTranslateCore"],
            path: "src/EngineMLX"
        ),
        .executableTarget(
            name: "mbt",
            dependencies: ["MenubarTranslateCore", "MTEngineLlama", "MTEngineMLX"],
            path: "mbt"
        ),
        .testTarget(
            name: "MenubarTranslateCoreTests",
            dependencies: ["MenubarTranslateCore", "MTEngineLlama", "MTEngineMLX"],
            path: "tests"
        ),
    ]
)
