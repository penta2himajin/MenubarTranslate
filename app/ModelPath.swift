import Foundation

/// GGUF path for the shipping app (ADR 0010).
/// `MBT_LLAMA_GGUF` → Application Support → repo-relative (swift run only).
enum ModelPath {
    static let fileName = "gemma-4-E2B_q4_0-it.gguf"

    static var applicationSupportFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MenubarTranslate/models/\(fileName)", isDirectory: false)
    }

    static func llamaGGUF() -> String {
        if let env = ProcessInfo.processInfo.environment["MBT_LLAMA_GGUF"], !env.isEmpty {
            return env
        }
        let support = applicationSupportFile
        if FileManager.default.fileExists(atPath: support.path) {
            return support.path
        }
        if Bundle.main.bundleIdentifier == "io.github.penta2himajin.MenubarTranslate" {
            return support.path
        }
        return "models/weights/\(fileName)"
    }
}
