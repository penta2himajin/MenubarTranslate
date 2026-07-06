// swift-tools-version:6.0
import PackageDescription
import Foundation

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

// ponytail: conditional xcframework — vendor/llama.xcframework is built by
// scripts/build-llama-xcframework.sh and .gitignored (too large for GitHub).
// Clean checkouts compile without it; MTEngineLlama degrades to an honest stub
// via `#if canImport(llama)`.  Running the script enables the real engine.
//
// Use an absolute path derived from #file so the check works regardless of the
// working directory when SwiftPM evaluates this manifest (e.g. in a sandboxed
// subprocess during `swift test`).
// In SwiftPM's manifest runner, #file expands to a relative path like
// "main/Package.swift" (the manifest runner places Package.swift under a "main/"
// subdirectory).  Two deletingLastPathComponent() calls walk up to the real
// package root regardless of the process working directory.
let _packageRoot = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()  // removes "Package.swift" → .../main
    .deletingLastPathComponent()  // removes "main"          → package root
    .path
let llamaVendored = FileManager.default.fileExists(
    atPath: _packageRoot + "/vendor/llama.xcframework")

var targets: [Target] = [
    .target(
        name: "MenubarTranslateCore",
        dependencies: [
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        path: "src",
        exclude: ["Core/Tests.swift", "EngineLlama", "EngineMLX"]
    ),
    .target(
        name: "MTEngineMLX",
        dependencies: [
            "MenubarTranslateCore",
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            // MLX for `Memory.clearCache()` — evict releases the Metal buffer cache
            // while keeping the runtime alive for a warm reload (ADR 0002).
            .product(name: "MLX", package: "mlx-swift"),
            // Concrete tokenizer implementation wrapped by the local tokenizer loader.
            // Product `Transformers` exports the `Tokenizers` module (target name).
            .product(name: "Transformers", package: "swift-transformers"),
        ],
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

// MTEngineLlama: link against the real xcframework when it is present, otherwise
// compile stub-only (no llama import → #if canImport(llama) selects the stub).
if llamaVendored {
    targets += [
        .binaryTarget(
            name: "llama",
            path: "vendor/llama.xcframework"
        ),
        .target(
            name: "MTEngineLlama",
            dependencies: ["MenubarTranslateCore", "llama"],
            path: "src/EngineLlama"
        ),
    ]
} else {
    targets += [
        .target(
            name: "MTEngineLlama",
            dependencies: ["MenubarTranslateCore"],
            path: "src/EngineLlama"
        ),
    ]
}

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
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        // mlx-swift is transitively pulled by mlx-swift-lm; declared directly so MTEngineMLX
        // can `import MLX` for `Memory.clearCache()` (evict releases the Metal buffer cache).
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.4"),
        // swift-transformers: provides `Tokenizers.AutoTokenizer`, the concrete tokenizer
        // implementation that MLXLMCommon's `TokenizerLoader` protocol wraps. Used for
        // local (offline) tokenizer loading from a model directory. Isolated to MTEngineMLX.
        .package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.14"),
    ],
    targets: targets
)
