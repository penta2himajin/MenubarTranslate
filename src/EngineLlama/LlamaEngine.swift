import Foundation
import MenubarTranslateCore

// ponytail: real engine under #if canImport(llama); stub in #else so clean
// checkouts build without the xcframework.  Run
// scripts/build-llama-xcframework.sh once to unlock the real path.

public enum LlamaPrefill {
    public static func chunkRanges(count: Int, batchSize: Int) -> [Range<Int>] {
        guard count > 0, batchSize > 0 else { return [] }
        var ranges: [Range<Int>] = []
        var i = 0
        while i < count {
            let end = min(i + batchSize, count)
            ranges.append(i..<end)
            i = end
        }
        return ranges
    }
}

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
    private var lastPromptTokens: [llama_token] = []
    private var nCtx: Int = 4096
    private var nCtxSeq: Int = 4096
    private var nBatch: Int = 512
    private var nSeqMax: Int = 8

    public init(modelPath: String) {
        self.modelPath = modelPath
    }

    // MARK: - TranslationEngine

    public func load() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                // Already loaded — idempotent.
                if self.model != nil { cont.resume(); return }

                BackendLifetime.ensureInitialised()

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
                // 4096: panel pastes exceed the ADR 0009 sentence-length 1024
                // (KV fills → "failed to find a memory slot" and a truncated
                // translation). Prefill is chunked at n_batch so compute buffers
                // stay at 512. MBT_N_CTX still overrides.
                let perSeq = ProcessInfo.processInfo.environment["MBT_N_CTX"]
                    .flatMap(UInt32.init) ?? 4096
                self.nSeqMax = ProcessInfo.processInfo.environment["MBT_N_SEQ_MAX"]
                    .flatMap(Int.init).map { max(1, $0) } ?? 8
                cparams.n_ctx = perSeq
                cparams.n_batch = 512
                cparams.n_seq_max = UInt32(self.nSeqMax)
                // Unified KV keeps n_ctx_seq = n_ctx (panel pastes still get 4096)
                // instead of dividing the cache across sequences.
                cparams.kv_unified = self.nSeqMax > 1
                cparams.n_outputs_max = UInt32(self.nSeqMax)

                guard let c = llama_init_from_model(m, cparams) else {
                    llama_model_free(m)
                    cont.resume(throwing: TranslationEngineError.unavailable(
                        "llama_new_context_with_model failed"))
                    return
                }

                self.model = m
                self.ctx = c
                self.nCtx = Int(llama_n_ctx(c))
                self.nCtxSeq = Int(llama_n_ctx_seq(c))
                self.nBatch = Int(cparams.n_batch)
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

    public func translateMany(_ items: [(String, LanguagePair)]) async throws -> [String] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String], Error>) in
            queue.async { [self] in
                guard let model = self.model, let ctx = self.ctx else {
                    cont.resume(throwing: TranslationEngineError.notLoaded)
                    return
                }
                do {
                    cont.resume(returning: try self.runMany(model: model, ctx: ctx, items: items))
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
                self.lastPromptTokens = []
                // ponytail: backend stays alive (ADR 0002); only weights are freed.
                cont.resume()
            }
        }
    }

    // MARK: - Inference

    private func runMany(
        model: OpaquePointer,
        ctx: OpaquePointer,
        items: [(String, LanguagePair)]
    ) throws -> [String] {
        if items.isEmpty { return [] }
        if items.count == 1 {
            return [try runInference(model: model, ctx: ctx, text: items[0].0, pair: items[0].1)]
        }
        var out: [String] = []
        out.reserveCapacity(items.count)
        var i = 0
        while i < items.count {
            let end = min(i + nSeqMax, items.count)
            let chunk = Array(items[i..<end])
            if chunk.count == 1 {
                out.append(try runInference(model: model, ctx: ctx, text: chunk[0].0, pair: chunk[0].1))
            } else {
                do {
                    out.append(contentsOf: try runParallel(model: model, ctx: ctx, items: chunk))
                } catch {
                    FileHandle.standardError.write(
                        Data("llama batch fallback serial: \(error)\n".utf8)
                    )
                    for item in chunk {
                        out.append(try runInference(model: model, ctx: ctx, text: item.0, pair: item.1))
                    }
                }
            }
            i = end
        }
        return out
    }

    private func runParallel(
        model: OpaquePointer,
        ctx: OpaquePointer,
        items: [(String, LanguagePair)]
    ) throws -> [String] {
        lastPromptTokens = []
        let vocab = llama_model_get_vocab(model)
        let mem = llama_get_memory(ctx)
        llama_memory_clear(mem, true)

        var tokenized: [[llama_token]] = []
        var families: [ModelFamily] = []
        tokenized.reserveCapacity(items.count)
        for item in items {
            let family = detectFamily(model)
            if family == .hunyuan, SamplingProfile.current == .modelCard {
                throw TranslationEngineError.unavailable("hunyuan sampling is per-sequence")
            }
            let prompt = renderPrompt(family, vocab: vocab, text: item.0, pair: item.1)
            let tokens = try tokenize(vocab, prompt)
            guard tokens.count < nCtxSeq else {
                throw TranslationEngineError.unavailable(
                    "input too long for context (\(tokens.count) tokens, n_ctx_seq=\(nCtxSeq))")
            }
            tokenized.append(tokens)
            families.append(family)
        }

        for seq in 0..<items.count {
            let tokens = tokenized[seq]
            if tokens.count > 1 {
                try decodeTokens(
                    ctx, tokens: Array(tokens.dropLast()), seq: Int32(seq), pos0: 0, logitsLast: false)
            }
        }
        try decodeLastTokens(ctx, tokenized: tokenized)

        let sparams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(sparams) else {
            throw TranslationEngineError.unavailable("llama_sampler_chain_init failed")
        }
        defer { llama_sampler_free(chain) }
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())

        var alive = Array(0..<items.count)
        var pos = tokenized.map { Int32($0.count) }
        var outputTokens = Array(repeating: [llama_token](), count: items.count)
        let maxGen = tokenized.map { nCtxSeq - $0.count }
        var genBatch = llama_batch_init(Int32(items.count), 0, 1)
        defer { llama_batch_free(genBatch) }

        while !alive.isEmpty {
            var next: [Int] = []
            for (bi, seq) in alive.enumerated() {
                let sampled = llama_sampler_sample(chain, ctx, Int32(bi))
                llama_sampler_accept(chain, sampled)
                if llama_vocab_is_eog(vocab, sampled) { continue }
                outputTokens[seq].append(sampled)
                if outputTokens[seq].count >= maxGen[seq] { continue }
                let i = next.count
                genBatch.token[i] = sampled
                genBatch.pos[i] = pos[seq]
                genBatch.n_seq_id[i] = 1
                genBatch.seq_id[i]![0] = Int32(seq)
                genBatch.logits[i] = 1
                pos[seq] += 1
                next.append(seq)
            }
            if next.isEmpty { break }
            genBatch.n_tokens = Int32(next.count)
            let rc = llama_decode(ctx, genBatch)
            if rc != 0 {
                throw TranslationEngineError.unavailable("llama_decode (batch gen) failed \(rc)")
            }
            alive = next
        }

        return zip(outputTokens, families).map { stripArtifacts(detokenize(vocab, $0), family: $1) }
    }

    private func detectFamily(_ model: OpaquePointer) -> ModelFamily {
        let arch = llamaMeta(model, key: "general.architecture") ?? ""
        let name = llamaMeta(model, key: "general.basename")
            ?? llamaMeta(model, key: "general.name") ?? ""
        if name.lowercased().contains("milmmt") { return .milmmt }
        if arch.contains("hunyuan") { return .hunyuan }
        if arch.hasPrefix("gemma4") { return .gemma4 }
        return .gemma
    }

    private func renderPrompt(
        _ family: ModelFamily, vocab: OpaquePointer?, text: String, pair: LanguagePair
    ) -> String {
        switch family {
        case .hunyuan:
            let bos = llama_vocab_bos(vocab)
            let bosText = bos < 0 ? nil : llama_vocab_get_text(vocab, bos).map { String(cString: $0) }
            return PromptBuilder.hunyuan(
                text: text, pair: pair, dialect: HunyuanDialect(bosToken: bosText))
        case .gemma4:
            return PromptBuilder.gemma4(text: text, pair: pair)
        case .milmmt:
            return PromptBuilder.milmmt(text: text, pair: pair)
        case .gemma:
            return PromptBuilder.gemma(text: text, pair: pair)
        }
    }

    private func tokenize(_ vocab: OpaquePointer?, _ prompt: String) throws -> [llama_token] {
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 32)
        let nTokens = llama_tokenize(
            vocab, prompt, Int32(prompt.utf8.count),
            &tokens, Int32(tokens.count), true, true)
        guard nTokens > 0 else {
            throw TranslationEngineError.unavailable("llama_tokenize returned \(nTokens)")
        }
        return Array(tokens.prefix(Int(nTokens)))
    }

    private func decodeTokens(
        _ ctx: OpaquePointer, tokens: [llama_token], seq: Int32, pos0: Int, logitsLast: Bool
    ) throws {
        for range in LlamaPrefill.chunkRanges(count: tokens.count, batchSize: nBatch) {
            let chunk = tokens[range]
            var batch = llama_batch_init(Int32(chunk.count), 0, 1)
            defer { llama_batch_free(batch) }
            let lastChunk = range.upperBound == tokens.count
            for (i, tok) in chunk.enumerated() {
                batch.token[i] = tok
                batch.pos[i] = Int32(pos0 + range.lowerBound + i)
                batch.n_seq_id[i] = 1
                batch.seq_id[i]![0] = seq
                batch.logits[i] = 0
            }
            if logitsLast, lastChunk {
                batch.logits[chunk.count - 1] = 1
            }
            batch.n_tokens = Int32(chunk.count)
            let rc = llama_decode(ctx, batch)
            if rc != 0 {
                throw TranslationEngineError.unavailable("llama_decode (prefill) failed \(rc)")
            }
        }
    }

    private func decodeLastTokens(_ ctx: OpaquePointer, tokenized: [[llama_token]]) throws {
        let n = tokenized.count
        var batch = llama_batch_init(Int32(n), 0, 1)
        defer { llama_batch_free(batch) }
        for seq in 0..<n {
            let tokens = tokenized[seq]
            let last = tokens[tokens.count - 1]
            batch.token[seq] = last
            batch.pos[seq] = Int32(tokens.count - 1)
            batch.n_seq_id[seq] = 1
            batch.seq_id[seq]![0] = Int32(seq)
            batch.logits[seq] = 1
        }
        batch.n_tokens = Int32(n)
        let rc = llama_decode(ctx, batch)
        if rc != 0 {
            throw TranslationEngineError.unavailable("llama_decode (batch logits) failed \(rc)")
        }
    }

    private func detokenize(_ vocab: OpaquePointer?, _ outputTokens: [llama_token]) -> String {
        var output = ""
        var buf = [CChar](repeating: 0, count: 256)
        for tok in outputTokens {
            let n = llama_token_to_piece(vocab, tok, &buf, Int32(buf.count), 0, false)
            if n > 0 {
                output += String(bytes: buf.prefix(Int(n)).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
            }
        }
        return output
    }

    private func runInference(
        model: OpaquePointer,
        ctx: OpaquePointer,
        text: String,
        pair: LanguagePair
    ) throws -> String {
        // Detect model family from metadata.
        let arch = llamaMeta(model, key: "general.architecture") ?? ""
        // MiLMMT is a Gemma 3 fine-tune, so it reports architecture "gemma3" while
        // using a completely different, template-free prompt. Architecture cannot
        // separate it from TranslateGemma — the name can.
        let name = llamaMeta(model, key: "general.basename")
            ?? llamaMeta(model, key: "general.name") ?? ""
        let family: ModelFamily = name.lowercased().contains("milmmt") ? .milmmt
            : arch.contains("hunyuan") ? .hunyuan
            : arch.hasPrefix("gemma4") ? .gemma4
            : .gemma

        // Get vocab pointer (b9878: tokenize/detokenize APIs take llama_vocab*).
        let vocab = llama_model_get_vocab(model)

        // Build prompt via the canonical PromptBuilder in core (shared with MLXEngine).
        let prompt: String
        switch family {
        case .hunyuan:
            // Hy-MT2-7B and Hy-MT2-1.8B ship different tokenizers; ask the model
            // which one it speaks instead of assuming (see HunyuanDialect).
            let bos = llama_vocab_bos(vocab)
            let bosText = bos < 0 ? nil : llama_vocab_get_text(vocab, bos).map { String(cString: $0) }
            prompt = PromptBuilder.hunyuan(
                text: text, pair: pair, dialect: HunyuanDialect(bosToken: bosText))
        case .gemma4:
            prompt = PromptBuilder.gemma4(text: text, pair: pair)
        case .milmmt:
            prompt = PromptBuilder.milmmt(text: text, pair: pair)
        case .gemma:
            prompt = PromptBuilder.gemma(text: text, pair: pair)
        }

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
        guard tokens.count < nCtxSeq else {
            throw TranslationEngineError.unavailable(
                "input too long for context (\(tokens.count) tokens, n_ctx_seq=\(nCtxSeq))")
        }

        let mem = llama_get_memory(ctx)
        let shared = zip(lastPromptTokens, tokens).prefix(while: { $0 == $1 }).count
        // Keep the shared prefix in KV; drop generation + the mismatched tail.
        // Identical prompts still need logits on the last prompt token.
        var keep = shared
        if keep == tokens.count { keep = max(0, keep - 1) }
        if keep == 0 {
            llama_memory_clear(mem, true)
        } else if !llama_memory_seq_rm(mem, 0, Int32(keep), -1) {
            llama_memory_clear(mem, true)
            keep = 0
        }
        lastPromptTokens = tokens

        let suffix = Array(tokens.dropFirst(keep))
        for range in LlamaPrefill.chunkRanges(count: suffix.count, batchSize: nBatch) {
            let chunk = suffix[range]
            var batch = llama_batch_init(Int32(chunk.count), 0, 1)
            defer { llama_batch_free(batch) }
            let lastChunk = range.upperBound == suffix.count
            for (i, tok) in chunk.enumerated() {
                batch.token[i] = tok
                batch.pos[i] = Int32(keep + range.lowerBound + i)
                batch.n_seq_id[i] = 1
                batch.seq_id[i]![0] = 0
                batch.logits[i] = 0
            }
            if lastChunk {
                batch.logits[chunk.count - 1] = 1
            }
            batch.n_tokens = Int32(chunk.count)
            if llama_decode(ctx, batch) != 0 {
                throw TranslationEngineError.unavailable("llama_decode (prefill) failed")
            }
        }

        // Build sampler chain.
        let sparams = llama_sampler_chain_default_params()
        guard let chain = llama_sampler_chain_init(sparams) else {
            throw TranslationEngineError.unavailable("llama_sampler_chain_init failed")
        }
        defer { llama_sampler_free(chain) }

        if family == .hunyuan, SamplingProfile.current == .modelCard {
            llama_sampler_chain_add(chain, llama_sampler_init_temp(0.7))
            llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.6, 1))
            llama_sampler_chain_add(chain, llama_sampler_init_top_k(20))
            llama_sampler_chain_add(chain, llama_sampler_init_penalties(64, 1.05, 0.0, 0.0))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(0xCAFE))
        } else {
            // Gemma3 always; Hy-MT2 under MBT_SAMPLING=greedy.
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        }

        // Generate until EOS or the KV cache is full.
        var outputTokens = [llama_token]()
        let maxGen = nCtx - tokens.count
        outputTokens.reserveCapacity(maxGen)
        var pos = Int32(tokens.count)

        var genBatch = llama_batch_init(1, 0, 1)
        defer { llama_batch_free(genBatch) }

        for _ in 0..<maxGen {
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

        return stripArtifacts(output, family: family)
    }

    // MARK: - Helpers

    private func llamaMeta(_ model: OpaquePointer, key: String) -> String? {
        var buf = [CChar](repeating: 0, count: 256)
        let n = llama_model_meta_val_str(model, key, &buf, buf.count)
        guard n > 0 else { return nil }
        return String(cString: buf)
    }

    private func stripArtifacts(_ s: String, family: ModelFamily) -> String {
        var out = s
        switch family {
        case .hunyuan:
            for marker in ["<|extra_0|>", "<|startoftext|>",
                           "<｜hy_Assistant｜>", "<｜hy_place▁holder▁no▁2｜>",
                           "<｜hy_begin▁of▁sentence｜>"] {
                out = out.replacingOccurrences(of: marker, with: "")
            }
        case .gemma4:
            if let r = out.range(of: "<turn|>") { out = String(out[..<r.lowerBound]) }
            for marker in ["<|turn>model", "<|turn>user", "<|turn>", "<turn|>"] {
                out = out.replacingOccurrences(of: marker, with: "")
            }
        case .milmmt:
            // Raw-prompt model: it can run on into a second translation block.
            // Cut at the first one rather than shipping the continuation.
            if let r = out.range(of: "Translate this from") {
                out = String(out[..<r.lowerBound])
            }
        case .gemma:
            if let r = out.range(of: "<end_of_turn>") { out = String(out[..<r.lowerBound]) }
            out = out.replacingOccurrences(of: "<start_of_turn>model", with: "")
            out = out.replacingOccurrences(of: "<start_of_turn>", with: "")
            out = out.replacingOccurrences(of: "<end_of_turn>", with: "")
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Which prompt/stop-token convention a loaded GGUF speaks, derived from
/// `general.architecture`.
private enum ModelFamily {
    case gemma      // TranslateGemma / Gemma 3: <start_of_turn> ... <end_of_turn>
    case gemma4     // Gemma 4: <|turn>role ... <turn|>
    case hunyuan    // Hy-MT2, either tokenizer (see HunyuanDialect)
    case milmmt     // MiLMMT-46: no chat template, raw "Translate this from ..." 
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
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranslationEngineError.unavailable("model file not found at \(modelPath)")
        }
        throw TranslationEngineError.unavailable(
            "llama.cpp not vendored — run scripts/build-llama-xcframework.sh")
    }

    /// Unreachable in practice: `load()` above always throws, so nothing can hold a
    /// loaded stub. `.notLoaded` is the honest answer if a caller gets here anyway.
    public func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        throw TranslationEngineError.notLoaded
    }

    public func evict() async {}
}

#endif
