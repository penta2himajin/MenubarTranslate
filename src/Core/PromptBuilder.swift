/// Canonical prompt renderers for the supported model families.
///
/// Lives in MenubarTranslateCore (pure Swift, no ML deps) so both MTEngineMLX
/// and MTEngineLlama render identical prompts — drift between the two is the
/// source of subtle quality regressions, so the single copy is intentional.
///
/// ponytail: two static funcs, no abstraction; add a protocol only if a third
/// model family with genuinely different dispatch needs lands.
public enum PromptBuilder {

    /// TranslateGemma-4B chat-template prompt.
    ///
    /// Rendered manually because the model's jinja template expects a custom
    /// content structure.  The tokenizer adds <bos> automatically
    /// (add_bos_token=true in tokenizer_config.json); this string starts at
    /// <start_of_turn> and ends with the opening `<start_of_turn>model\n` turn
    /// so the model continues directly into the translation.
    ///
    /// The trailing newline after `model` is load-bearing: the official gemma
    /// template terminates the turn header with "\n", and omitting it pushed
    /// Q4_K_M greedy decoding off-distribution — EN→JA emitted instruction-like
    /// prefixes and wrong-language output (docs/bench/2026-07-06-m2.md).
    ///
    /// The triple-newline before the user text is the separator the original
    /// TranslateGemma fine-tune was trained on.
    public static func gemma(text: String, pair: LanguagePair) -> String {
        """
        <start_of_turn>user
        You are a professional \(pair.sourceName) (\(pair.sourceCode)) to \(pair.targetName) (\(pair.targetCode)) translator. Your goal is to accurately convey the meaning and nuances of the original \(pair.sourceName) text while adhering to \(pair.targetName) grammar, vocabulary, and cultural sensitivities.
        Produce only the \(pair.targetName) translation, without any additional explanations or commentary. Please translate the following \(pair.sourceName) text into \(pair.targetName):


        \(text)<end_of_turn>
        <start_of_turn>model

        """
    }

    /// Hy-MT2 wire-format prompt (no system prompt).
    ///
    /// The instruction body is verbatim from the Hy-MT2 model card; only the
    /// framing tokens differ between checkpoints — see `HunyuanDialect`.
    public static func hunyuan(
        text: String,
        pair: LanguagePair,
        dialect: HunyuanDialect = .startOfText
    ) -> String {
        let instruction = "Translate the following text into \(pair.targetName). "
            + "Note that you should only output the translated result without any additional explanation:\n\n"
        switch dialect {
        case .startOfText:
            return "<|startoftext|>\(instruction)\(text)<|extra_0|>"
        case .hyTurn:
            return "<｜hy_begin▁of▁sentence｜><｜hy_User｜>\(instruction)\(text)<｜hy_Assistant｜>"
        }
    }
}

/// Which of the two incompatible Hy-MT2 token sets a checkpoint speaks.
///
/// Hy-MT2 ships the same model family under two tokenizers. Hy-MT2-7B uses the
/// legacy Hunyuan markers (`<|startoftext|>` … `<|extra_0|>`); Hy-MT2-1.8B uses
/// fullwidth turn markers (`<｜hy_User｜>` / `<｜hy_Assistant｜>`). Neither set
/// appears in the other's vocabulary, so a prompt in the wrong dialect is not
/// merely off-template — the framing tokens tokenize as ordinary text and the
/// model sees no turn boundary at all.
///
/// ponytail: derived from the model's own BOS token rather than a name or size,
/// so a new checkpoint that picks either tokenizer is classified without a
/// hardcoded table.
public enum HunyuanDialect: Sendable {
    /// Hy-MT2-7B: `<|startoftext|>{instruction}{text}<|extra_0|>`
    case startOfText
    /// Hy-MT2-1.8B: `<｜hy_begin▁of▁sentence｜><｜hy_User｜>{…}<｜hy_Assistant｜>`
    case hyTurn

    /// Classify from the BOS token text reported by the loaded model
    /// (`llama_vocab_get_text(vocab, llama_vocab_bos(vocab))`, or `bos_token`
    /// in `tokenizer_config.json`).
    ///
    /// Unknown or missing metadata falls back to `.startOfText`, the format
    /// that shipped and is measured in ADR 0008.
    public init(bosToken: String?) {
        self = bosToken?.contains("hy_begin") == true ? .hyTurn : .startOfText
    }
}
