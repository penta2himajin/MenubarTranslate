import Foundation
import MenubarTranslateCore

// ponytail: real engine under #if canImport(llama); stub in #else so clean
// checkouts build without the xcframework.  Run
// scripts/build-llama-xcframework.sh once to unlock the real path.

#if canImport(llama)
import llama

/// llama.cpp / Metal inference backend.
///
/// Weight-level residency (ADR 0002): `load()`/`evict()` move only the model +
/// context; `llama_backend_init` is retained across the cycle (process-wide
/// singleton via `BackendLifetime`) so a warm reload is cheap.
///
/// Concurrency: all C-pointer mutations are confined to `queue` (serial).
/// The class is `@unchecked Sendable` because the C pointers are not Swift
/// Concurrency-aware; the serial queue provides the required exclusion.
public final class LlamaEngine: TranslationEngine, @unchecked Sendable {
    private let modelPath: String
    // ponytail: serial queue for C-pointer exclusion; per-account queues if
    // parallelism ever matters.
    private let queue = DispatchQueue(label: "mbt.llama-engine")
    private var model: OpaquePointer? = nil   // llama_model*
    private var ctx: OpaquePointer? = nil     // llama_context*

    public init(modelPath: String) {
        self.modelPath = modelPath
        BackendLifetime.ensureInitialised()
    }

    // MARK: - TranslationEngine

    public func load() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                // Already loaded — idempotent.
                if self.model != nil { cont.resume(); return }

                guard FileManager.default.fileExists(atPath: self.modelPath) else {
                    cont.resume(throwing: TranslationEngineError.unavailable(
                        "model file not found at \(self.modelPath)"))
                    return
                }

                var mparams = llama_model_default_params()
                mparams.n_gpu_layers = 99   // all layers → Metal

                guard let m = llama_model_load_from_file(self.modelPath, mparams) else {
                    cont.resume(throwing: TranslationEngineError.unavailable(
                        "llama_model_load_from_file failed for \(self.modelPath)"))
                    return
                }

                var cparams = llama_context_default_params()
                cparams.n_ctx = 4096
                cparams.n_batch = 512

                guard let c = llama_init_from_model(m, cparams) else {
                    llama_model_free(m)
                    cont.resume(throwing: TranslationEngineError.unavailable(
                        "llama_new_context_with_model failed"))
                    return
                }

                self.model = m
                self.ctx = c
                cont.resume()
            }
        }
    }

    public func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async { [self] in
                guard let model = self.model, let ctx = self.ctx else {
                    cont.resume(throwing: TranslationEngineError.notLoaded)
                    return
                }
                do {
                    let result = try self.runInference(model: model, ctx: ctx, text: text, pair: pair)
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    public func evict() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if let c = self.ctx { llama_free(c); self.ctx = nil }
                if let m = self.model { llama_model_free(m); self.model = nil }
                // ponytail: backend stays alive (ADR 0002); only weights are freed.
                cont.resume()
            }
        }
    }

    // MARK: - Inference

    private func runInference(
        model: OpaquePointer,
        ctx: OpaquePointer,
        text: String,
        pair: LanguagePair
    ) throws -> String {
        // Detect model family from metadata.
        let arch = llamaMeta(model, key: "general.architecture") ?? ""
        let isHunyuan = arch.hasPrefix("hunyuan") || arch.contains("hunyuan")

        // Build prompt via the canonical PromptBuilder in core (shared with MLXEngine).
        let prompt: String
        if isHunyuan {
            prompt = PromptBuilder.hunyuan(text: text, pair: pair)
        } else {
            // Default: gemma3
            prompt = PromptBuilder.gemma(text: text, pair: pair)
        }

        // Get vocab pointer (b9878: tokenize/detokenize APIs take llama_vocab*).
        let vocab = llama_model_get_vocab(model)

        // Tokenize (add_special=true: BOS handling follows model metadata).
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 32)
        let nTokens = llama_tokenize(
            vocab,
            prompt,
            Int32(prompt.utf8.count),
            &tokens,
            Int32(tokens.count),
            true,   // add_special
            true    // parse_special
        )
        guard nTokens > 0 else {
            throw TranslationEngineError.unavailable("llama_tokenize returned \(nTokens)")
        }
        tokens = Array(tokens.prefix(Int(nTokens)))

        // Reset KV cache for a clean context.
        llama_memory_clear(llama_get_memory(ctx), true)

        // Prefill: decode the prompt in one batch.
        var batch = llama_batch_init(Int32(tokens.count), 0, 1)
        defer { llama_batch_free(batch) }

        for (i, tok) in tokens.enumerated() {
            batch.token[i] = tok
            batch.pos[i] = Int32(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]![0] = 0
            batch.logits[i] = 0
        }
        batch.logits[tokens.count - 1] = 1   // only need logits for last prompt token
        batch.n_tokens = Int32(tokens.count)

        if llama_decode(ctx, batch) != 0 {
            throw TranslationEngineError.unavailable("llama_decode (prefill) failed")
        }

        // Build sampler chain.
        let sparams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(sparams) else {
            throw TranslationEngineError.unavailable("llama_sampler_chain_init failed")
        }
        defer { llama_sampler_free(chain) }

        if isHunyuan {
            llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.6, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(20))
            llama_sampler_chain_add(chain, llama_sampler_init_penalties(64, 1.05, 0.0, 0.0))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(0xCAFE))
        } else {
            // Gemma3: greedy
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        }

        // Generate up to 512 tokens.
        var outputTokens = [llama_token]()
        outputTokens.reserveCapacity(512)
        var pos = Int32(tokens.count)

        var genBatch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(genBatch) }

        for _ in 0..<512 {
            let sampled = llama_sampler_sample(chain, ctx, -1)
            // llama_vocab_is_eog covers EOS + EOT + any model-specific end tokens.
            if llama_vocab_is_eog(vocab, sampled) { break }

            outputTokens.append(sampled)

            // Decode the single new token.
            genBatch.token[0] = sampled
            genBatch.pos[0] = pos
            genBatch.n_seq_id[0] = 1
            genBatch.seq_id[0]![0] = 0
            genBatch.logits[0] = 1
            genBatch.n_tokens = 1

            if llama_decode(ctx, genBatch) != 0 { break }
            pos += 1
        }

        // Detokenize (b9878: llama_token_to_piece takes llama_vocab*).
        var output = ""
        var buf = [CChar](repeating: 0, count: 256)
        for tok in outputTokens {
            let n = llama_token_to_piece(vocab, tok, &buf, Int32(buf.count), 0, false)
            if n > 0 {
                output += String(bytes: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
            }
        }

        return stripArtifacts(output, isHunyuan: isHunyuan)
    }

    // MARK: - Helpers

    private func llamaMeta(_ model: OpaquePointer, key: String) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        let n = llama_model_meta_val_str(model, key, &buf, buf.count)
        guard n > 0 else { return nil }
        return String(cString: buf)
    }

    private func stripArtifacts(_ s: String, isHunyuan: Bool) -> String {
        var out = s
        if isHunyuan {
            for marker in ["<|extra_0|>", "<|startoftext|>",
                           "<｜hy_Assistant｜>", "<｜hy_place▁holder▁no▁2｜>",
                           "<｜hy_begin▁of▁sentence｜>"] {
                out = out.replacingOccurrences(of: marker, with: "")
            }
        } else {
            // Gemma
            if let r = out.range(of: "<end_of_turn>") { out = String(out[..<r.lowerBound]) }
            out = out.replacingOccurrences(of: "<start_of_turn>model", with: "")
            out = out.replacingOccurrences(of: "<start_of_turn>", with: "")
            out = out.replacingOccurrences(of: "<end_of_turn>", with: "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Backend lifetime

/// Process-wide singleton: initialises llama_backend exactly once and retains it
/// across load/evict cycles (ADR 0002 — amortises Metal/runtime init).
private enum BackendLifetime {
    nonisolated(unsafe) private static var once = false
    private static let lock = NSLock()

    static func ensureInitialised() {
        lock.lock(); defer { lock.unlock() }
        if once { return }
        llama_backend_init()
        once = true
    }
}

#else

// MARK: - Stub (no llama.xcframework)

/// llama.cpp engine stub used when vendor/llama.xcframework is absent.
///
/// `load()` always throws `.unavailable` with a clear message so callers
/// degrade gracefully.  Run scripts/build-llama-xcframework.sh to unlock
/// the real engine.
public final class LlamaEngine: TranslationEngine {
    private let modelPath: String

    public init(modelPath: String) {
        self.modelPath = modelPath
    }

    public func load() async throws {
        // STUB — implementation pending
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranslationEngineError.unavailable("model file not found at \(modelPath)")
        }
        throw TranslationEngineError.unavailable(
            "llama.cpp not vendored — run scripts/build-llama-xcframework.sh")
    }

    public func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        guard false else { throw TranslationEngineError.notLoaded }
        return ""
    }

    public func evict() async {}
}

#endif
