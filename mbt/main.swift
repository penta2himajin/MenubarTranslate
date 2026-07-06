import Foundation
import MenubarTranslateCore
import MTEngineLlama
import MTEngineMLX

#if canImport(Darwin)
import Darwin
#endif

let args = Array(CommandLine.arguments.dropFirst())

var stdinText: String?
if isatty(FileHandle.standardInput.fileDescriptor) == 0 {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    stdinText = String(data: data, encoding: .utf8)
}

let out = FileHandleSink(FileHandle.standardOutput)
let err = FileHandleSink(FileHandle.standardError)

// Resolve model paths from environment; driver passes these through to factories.
let llamaPath = ProcessInfo.processInfo.environment["MBT_LLAMA_GGUF"]
    ?? "models/weights/translategemma-4b-it-Q4_K_M.gguf"
let mlxDir = ProcessInfo.processInfo.environment["MBT_MLX_DIR"]
    ?? "models/weights/translategemma-mlx"

let factories: [String: (String) -> any TranslationEngine] = [
    "llama": { path in LlamaEngine(modelPath: path) },
    "mlx":   { path in MLXEngine(modelDirectory: path) },
]

let code = await CommandLineDriver().run(
    args, stdin: stdinText, out: out, err: err, engineFactories: factories
)
// _exit, not exit: llama.cpp b9878 aborts in a ggml-metal static destructor at process
// teardown (upstream GGML_ASSERT in ggml-metal-device.m:622), which would corrupt the
// exit code to 134 after a successful run. All output goes through unbuffered
// FileHandle writes, so skipping atexit/destructors loses nothing.
_exit(code)
