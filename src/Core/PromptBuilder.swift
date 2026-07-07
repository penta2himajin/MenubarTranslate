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
    /// <start_of_turn> and ends with the opening <start_of_turn>model turn
    /// so the model continues directly into the translation.
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

    /// Hy-MT2 wire-format prompt (no system prompt; BOS is supplied by the
    /// tokenizer via add_special=true on llama_tokenize or applyChatTemplate).
    ///
    /// Format: <|startoftext|>{instruction}\n\n{text}<|extra_0|>
    /// The model continues after <|extra_0|> with the translation.
    public static func hunyuan(text: String, pair: LanguagePair) -> String {
        "<|startoftext|>Translate the following text into \(pair.targetName). "
            + "Note that you should only output the translated result without any additional explanation:\n\n"
            + "\(text)<|extra_0|>"
    }
}
