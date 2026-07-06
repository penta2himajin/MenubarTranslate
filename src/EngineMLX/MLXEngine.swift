import Foundation
import Hub
import MenubarTranslateCore
import MLX
import MLXLLM
import MLXLMCommon
@preconcurrency import Tokenizers

/// MLX / Apple-Silicon inference backend (Wave 1).
///
/// Loads a quantised MLX model directory and runs on-device inference via the
/// `mlx-swift-lm` stack. The directory must be a self-contained MLX model
/// (`config.json`, weights, tokenizer files) — loading is strictly local (no
/// network); the `TokenizerLoader` below reads the tokenizer from the same
/// directory via `Tokenizers.AutoTokenizer`.
///
/// Weight-level residency (ADR 0002): `load()`/`evict()` move only the model
/// container; the MLX runtime and Metal device stay alive across the cycle so a
/// reload is cheap. `evict()` drops the container and clears the MLX buffer
/// cache.
///
/// Concurrency: the caller (`TranslationService` is single-context) serialises
/// load/translate/evict, so the mutable `container` is guarded by that contract
/// rather than an internal lock.
public final class MLXEngine: TranslationEngine, @unchecked Sendable {
    private let modelDirectory: String
    private var container: ModelContainer?  // nil = evicted
    private var modelType: String = ""

    public init(modelDirectory: String) {
        self.modelDirectory = modelDirectory
    }

    public func load() async throws {
        guard FileManager.default.fileExists(atPath: modelDirectory) else {
            throw TranslationEngineError.unavailable(
                "model directory not found at \(modelDirectory)")
        }

        // Read model_type from config.json for prompt dispatch (gemma3 vs hunyuan vs default).
        let configURL = URL(fileURLWithPath: modelDirectory)
            .appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let mt = json["model_type"] as? String {
            modelType = mt
        }

        // Register custom model types that aren't in LLMTypeRegistry.shared by default.
        // Idempotent: re-registering with the same key just overwrites with the same value.
        await LLMTypeRegistry.shared.registerModelType("hunyuan_v1_dense") { data in
            let config = try JSONDecoder.json5().decode(HunYuanDenseV1Configuration.self, from: data)
            return HunYuanDenseV1Model(config)
        }

        // Load from a local file:// URL — no downloader, no network.
        let dirURL = URL(fileURLWithPath: modelDirectory)
        container = try await LLMModelFactory.shared.loadContainer(
            from: dirURL, using: LocalTokenizerLoader())

        // Per-model stop-token configuration so generation terminates at the right
        // token and template artifacts do not leak into the decoded output.
        await configureStopTokens()
    }

    public func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        guard let container = container else { throw TranslationEngineError.notLoaded }

        // Build the prompt + generation parameters keyed on model_type.
        let tokens: [Int]
        let parameters: GenerateParameters
        let stripper: (String) -> String

        switch modelType {
        case "gemma3":
            // TranslateGemma-4B: render via shared PromptBuilder (canonical source in core).
            let prompt = PromptBuilder.gemma(text: text, pair: pair)
            tokens = await container.encode(prompt)
            parameters = GenerateParameters(maxTokens: 512, temperature: 0.01)
            stripper = Self.stripGemma
        default:
            if modelType.contains("hunyuan") {
                // Hy-MT2: chat-message based prompt via the model's chat template.
                let message = Self.hunyuanMessage(text: text, pair: pair)
                let messages: [[String: any Sendable]] = [
                    ["role": "user", "content": message],
                ]
                tokens = try await container.perform { ctx in
                    try ctx.tokenizer.applyChatTemplate(messages: messages)
                }
                parameters = GenerateParameters(maxTokens: 512, temperature: 0.7, topP: 0.6)
                stripper = Self.stripHunyuan
            } else {
                // Generic fallback.
                let prompt = "Translate the following text into \(pair.targetName):\n\n\(text)"
                tokens = await container.encode(prompt)
                parameters = GenerateParameters(maxTokens: 512, temperature: 0.3)
                stripper = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }

        let input = LMInput(tokens: MLXArray(tokens))
        let stream = try await container.generate(input: input, parameters: parameters)

        var output = ""
        for await generation in stream {
            if let chunk = generation.chunk {
                output += chunk
            }
        }
        return stripper(output)
    }

    public func evict() async {
        container = nil
        // Release the MLX/Metal buffer cache while keeping the device alive so a
        // warm reload is cheap (ADR 0002).
        Memory.clearCache()
    }

    // MARK: - Stop-token configuration

    private func configureStopTokens() async {
        guard let container = container else { return }
        switch modelType {
        case "gemma3":
            // The model emits <end_of_turn> to finish; register it as an extra EOS
            // so the generation loop stops before emitting it.
            await container.update { ctx in
                ctx.configuration.extraEOSTokens.insert("<end_of_turn>")
            }
        default:
            if modelType.contains("hunyuan") {
                // eos_token_id (120020) is loaded from generation_config.json; add the
                // known special tokens as decoded stop-strings as a safety net.
                await container.update { ctx in
                    ctx.configuration.stopStrings = [
                        "<|extra_0|>", "<|startoftext|>",
                        "<｜hy_Assistant｜>", "<｜hy_place▁holder▁no▁2｜>",
                        "<｜hy_begin▁of▁sentence｜>",
                    ]
                }
            }
        }
    }

    // MARK: - Prompt builders (MLX-specific; shared prompt roots live in PromptBuilder)

    private static func hunyuanMessage(text: String, pair: LanguagePair) -> String {
        """
        Translate the following text into \(pair.targetName). Note that you should only output the translated result without any additional explanation:

        \(text)
        """
    }

    // MARK: - Output stripping

    private static func stripGemma(_ output: String) -> String {
        // Cut at the first <end_of_turn> (the turn boundary) and drop any trailing
        // template scaffolding the model might have echoed.
        var s = output
        if let range = s.range(of: "<end_of_turn>") {
            s = String(s[..<range.lowerBound])
        }
        s = s.replacingOccurrences(of: "<start_of_turn>model", with: "")
        s = s.replacingOccurrences(of: "<start_of_turn>", with: "")
        s = s.replacingOccurrences(of: "<end_of_turn>", with: "")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripHunyuan(_ output: String) -> String {
        var s = output
        for marker in [
            "<|extra_0|>", "<|startoftext|>",
            "<｜hy_Assistant｜>", "<｜hy_place▁holder▁no▁2｜>",
            "<｜hy_begin▁of▁sentence｜>",
        ] {
            s = s.replacingOccurrences(of: marker, with: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Local tokenizer loader

/// A `TokenizerLoader` that loads `Tokenizers.AutoTokenizer` from a local model
/// directory. No network access — the directory must contain the tokenizer files
/// (`tokenizer.json`, `tokenizer_config.json`, `chat_template.jinja`, …).
///
/// `MLXLMCommon.Tokenizer` is a protocol; `swift-transformers`' `Tokenizer` is a
/// concrete type with a slightly different surface (notably `decode(tokens:)`
/// instead of `decode(tokenIds:)`, and `applyChatTemplate(messages:)` taking
/// `[[String: String]]`). `TokenizerBridge` adapts the two.
private struct LocalTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        // Normal loading path.
        // `TokenizersBackend` tokenizer_class — swift-transformers doesn't know this class;
        // the underlying tokenizer.json is a standard BPE file.  Patch the config's class to
        // "PreTrainedTokenizer" (maps to BPETokenizer) so the load succeeds without modification
        // of the on-disk weights.
        let configURL = directory.appendingPathComponent("tokenizer_config.json")
        let dataURL   = directory.appendingPathComponent("tokenizer.json")
        if let configData = try? Data(contentsOf: configURL),
           var configDict = try? JSONSerialization.jsonObject(with: configData) as? [NSString: Any],
           let tokenData  = try? Data(contentsOf: dataURL),
           let tokenDict  = try? JSONSerialization.jsonObject(with: tokenData) as? [NSString: Any]
        {
            if let cls = configDict["tokenizer_class"] as? String, cls == "TokenizersBackend" {
                // swift-transformers doesn't know "TokenizersBackend"; the underlying
                // tokenizer.json is a standard BPE — use PreTrainedTokenizer instead.
                configDict["tokenizer_class"] = "PreTrainedTokenizer" as NSString
                // Embed the jinja chat template so applyChatTemplate works; the template
                // file takes precedence over any in-config template (there isn't one here).
                let jinjURL = directory.appendingPathComponent("chat_template.jinja")
                if let jinja = try? String(contentsOf: jinjURL, encoding: .utf8) {
                    configDict["chat_template"] = jinja as NSString
                }
            }
            let tc = Config(configDict)
            let td = Config(tokenDict)
            let upstream = try Tokenizers.AutoTokenizer.from(tokenizerConfig: tc, tokenizerData: td)
            return TokenizerBridge(upstream)
        }

        let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

/// Adapts `swift-transformers`' `Tokenizer` to `MLXLMCommon.Tokenizer`.
private struct TokenizerBridge: MLXLMCommon.Tokenizer, @unchecked Sendable {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        // swift-transformers uses `decode(tokens:)` instead of `decode(tokenIds:)`.
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        // swift-transformers' applyChatTemplate takes [[String: String]] content;
        // coerce the Sendable values to strings (roles and string content pass
        // through unchanged). Tool/additional-context support is not needed for
        // the translation prompt path.
        let stringMessages: [[String: String]] = messages.map { msg in
            msg.mapValues { ($0 as? String) ?? "\($0)" }
        }
        return try upstream.applyChatTemplate(messages: stringMessages)
    }
}
