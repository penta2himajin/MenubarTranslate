import Foundation

/// Which decoder the translation engines run.
///
/// ADR 0008 compared TranslateGemma against Hy-MT2 without holding the decoder
/// fixed: gemma was measured greedy on both runtimes, while every Hy-MT2 config
/// used the model card's sampling (temp 0.7 / top-p 0.6 / top-k 20 / repetition
/// penalty 1.05). The Hy-MT2-1.8B quality verdict in that ADR — duplicated
/// clauses and hallucinated content — is exactly what a small model does under
/// stochastic sampling, so the two families were never comparable. This switch
/// exists to re-measure them under the same decoder.
///
/// `.greedy` is deliberately *pure* greedy, with no repetition penalty, so a
/// Hy-MT2 run is byte-for-byte comparable with the gemma rows rather than
/// merely close to them.
///
/// Measured on Hy-MT2-1.8B (`docs/bench/2026-07-27-hymt18b-*.md`): greedy cuts
/// p95 from 1567 ms to 657 ms but does not repair the quality verdict — the
/// duplicated clauses, misspellings and mistranslated proper nouns survive both
/// decoders, so ADR 0008's rejection of the 1.8B stands. Hy-MT2-7B was left
/// unmeasured by choice (too slow to be a candidate regardless of decoder), so
/// `.modelCard` remains the shipped default on evidence for 1.8B only.
///
/// ponytail: selected by environment rather than plumbed through the engine
/// APIs — the repo already picks bench artifacts by env (`MBT_MLX_DIR` &c.).
/// Kept rather than folded into a constant because the 7B decoder question is
/// open, not answered.
public enum SamplingProfile: Sendable {
    /// The values published on the model card (Hy-MT2: temp 0.7 / top-p 0.6).
    case modelCard
    /// Argmax, no penalties — what the gemma path already does.
    case greedy

    /// Read from `MBT_SAMPLING`; anything other than `greedy` keeps the
    /// shipped behaviour.
    public static var current: SamplingProfile {
        SamplingProfile(env: ProcessInfo.processInfo.environment["MBT_SAMPLING"])
    }

    public init(env: String?) {
        self = env == "greedy" ? .greedy : .modelCard
    }
}
