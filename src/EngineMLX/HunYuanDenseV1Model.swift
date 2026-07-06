// HunYuanDenseV1Model.swift — MLX Swift model for hunyuan_v1_dense architecture.
//
// HunYuan Dense V1 is LLaMA-like with per-layer QK RMSNorm in the attention.
// Weight keys: `self_attn.query_layernorm.weight` and `self_attn.key_layernorm.weight`
// are the only additions vs LlamaModel. Everything else (MLP, norms, RoPE, embeddings)
// is identical to the LLaMA path in mlx-swift-lm.
//
// rope_scaling.type = "dynamic" with factor = 1.0 is treated as standard RoPE (no
// scaling), matching the upstream Python behaviour for factor == 1.
//
// Registration happens in MLXEngine.load() before calling LLMModelFactory so the
// factory can construct the model for the hy-mt2 weights.

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXNN

// MARK: - Configuration

/// Decodes HunYuan Dense V1 `config.json`. Field mapping is identical to Llama
/// except `rope_scaling.type = "dynamic"` (handled explicitly below) and a handful
/// of extra keys that are decoded with `decodeIfPresent` / ignored.
struct HunYuanDenseV1Configuration: Codable, Sendable {

    var hiddenSize: Int
    var hiddenLayers: Int
    var intermediateSize: Int
    var attentionHeads: Int
    var headDimensions: Int?
    var rmsNormEps: Float
    var vocabularySize: Int
    var kvHeads: Int
    var maxPositionEmbeddings: Int?
    var ropeTheta: Float = 10_000
    var ropeTraditional: Bool = false
    var tieWordEmbeddings: Bool = true
    var attentionBias: Bool = false
    var mlpBias: Bool = false
    // useQKNorm is not consumed in Swift (the weight keys load automatically),
    // but we decode it to avoid a decoding error if strict mode is on.
    var useQKNorm: Bool = false

    var resolvedHeadDimensions: Int {
        headDimensions ?? (hiddenSize / attentionHeads)
    }

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case hiddenLayers = "num_hidden_layers"
        case intermediateSize = "intermediate_size"
        case attentionHeads = "num_attention_heads"
        case headDimensions = "head_dim"
        case rmsNormEps = "rms_norm_eps"
        case vocabularySize = "vocab_size"
        case kvHeads = "num_key_value_heads"
        case maxPositionEmbeddings = "max_position_embeddings"
        case ropeTheta = "rope_theta"
        case ropeTraditional = "rope_traditional"
        case tieWordEmbeddings = "tie_word_embeddings"
        case attentionBias = "attention_bias"
        case mlpBias = "mlp_bias"
        case useQKNorm = "use_qk_norm"
        // rope_scaling decoded manually to handle "dynamic" type
        case ropeScaling = "rope_scaling"
    }

    // rope_scaling: only used for RoPE init; "dynamic" with factor=1.0 → scale=1.0
    // We store the raw dict so initializeRope can parse standard types if needed.
    private var ropeScaling: [String: StringOrNumber]?

    init(from decoder: Swift.Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hiddenSize       = try c.decode(Int.self,   forKey: .hiddenSize)
        hiddenLayers     = try c.decode(Int.self,   forKey: .hiddenLayers)
        intermediateSize = try c.decode(Int.self,   forKey: .intermediateSize)
        attentionHeads   = try c.decode(Int.self,   forKey: .attentionHeads)
        headDimensions   = try c.decodeIfPresent(Int.self, forKey: .headDimensions)
        rmsNormEps       = try c.decode(Float.self, forKey: .rmsNormEps)
        vocabularySize   = try c.decode(Int.self,   forKey: .vocabularySize)
        kvHeads          = try c.decodeIfPresent(Int.self, forKey: .kvHeads) ?? attentionHeads
        maxPositionEmbeddings = try c.decodeIfPresent(Int.self, forKey: .maxPositionEmbeddings)
        if let v = try c.decodeIfPresent(Float.self, forKey: .ropeTheta) { ropeTheta = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .ropeTraditional) { ropeTraditional = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .tieWordEmbeddings) { tieWordEmbeddings = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .attentionBias) { attentionBias = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .mlpBias) { mlpBias = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .useQKNorm) { useQKNorm = v }
        ropeScaling = try c.decodeIfPresent([String: StringOrNumber].self, forKey: .ropeScaling)
    }

    // Returns a RoPELayer configured for this model.  HyMT uses
    // rope_scaling.type = "dynamic" which mlx-swift-lm doesn't handle natively;
    // factor = 1.0 means no scaling → plain RoPE.
    func makeRoPE(dims: Int) -> RoPELayer {
        if let rs = ropeScaling,
           case .string(let t) = rs["type"] ?? rs["rope_type"],
           t == "dynamic"
        {
            let scale = 1.0 / (rs["factor"]?.asFloat() ?? 1.0)
            return RoPE(dimensions: dims, traditional: ropeTraditional, base: ropeTheta, scale: scale)
        }
        return initializeRope(
            dims: dims, base: ropeTheta, traditional: ropeTraditional,
            scalingConfig: ropeScaling, maxPositionEmbeddings: maxPositionEmbeddings)
    }
}

// MARK: - Attention with QK norm

final class HunYuanDenseV1Attention: Module {

    let config: HunYuanDenseV1Configuration
    let scale: Float

    @ModuleInfo(key: "q_proj") var wq: Linear
    @ModuleInfo(key: "k_proj") var wk: Linear
    @ModuleInfo(key: "v_proj") var wv: Linear
    @ModuleInfo(key: "o_proj") var wo: Linear
    @ModuleInfo(key: "query_layernorm") var queryLayerNorm: RMSNorm
    @ModuleInfo(key: "key_layernorm")   var keyLayerNorm:   RMSNorm

    let rope: RoPELayer

    init(_ config: HunYuanDenseV1Configuration) {
        self.config = config

        let dim     = config.hiddenSize
        let heads   = config.attentionHeads
        let kvHeads = config.kvHeads
        let headDim = config.resolvedHeadDimensions
        self.scale  = pow(Float(headDim), -0.5)

        self._wq.wrappedValue = Linear(dim, heads * headDim, bias: config.attentionBias)
        self._wk.wrappedValue = Linear(dim, kvHeads * headDim, bias: config.attentionBias)
        self._wv.wrappedValue = Linear(dim, kvHeads * headDim, bias: config.attentionBias)
        self._wo.wrappedValue = Linear(heads * headDim, dim, bias: config.attentionBias)

        // QK norm: applied per head after projection, dimension = headDim
        self._queryLayerNorm.wrappedValue = RMSNorm(dimensions: headDim, eps: config.rmsNormEps)
        self._keyLayerNorm.wrappedValue   = RMSNorm(dimensions: headDim, eps: config.rmsNormEps)

        self.rope = config.makeRoPE(dims: headDim)
    }

    func callAsFunction(
        _ x: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache?
    ) -> MLXArray {
        let (B, L) = (x.dim(0), x.dim(1))
        let heads   = config.attentionHeads
        let kvHeads = config.kvHeads

        var queries = wq(x).reshaped(B, L, heads,   -1).transposed(0, 2, 1, 3)
        var keys    = wk(x).reshaped(B, L, kvHeads, -1).transposed(0, 2, 1, 3)
        let values  = wv(x).reshaped(B, L, kvHeads, -1).transposed(0, 2, 1, 3)

        // QK RMSNorm — applied before RoPE, per the HunYuan implementation
        queries = queryLayerNorm(queries)
        keys    = keyLayerNorm(keys)

        let offset = cache?.ropeOffset
        queries = applyRotaryPosition(rope, to: queries, offset: offset)
        keys    = applyRotaryPosition(rope, to: keys,    offset: offset)

        let out = attentionWithCacheUpdate(
            queries: queries, keys: keys, values: values,
            cache: cache, scale: scale, mask: mask
        )
        .transposed(0, 2, 1, 3)
        .reshaped(B, L, -1)
        return wo(out)
    }
}

// MARK: - Transformer block (reuses LlamaMLP shape via key names)

final class HunYuanDenseV1TransformerBlock: Module {

    @ModuleInfo(key: "self_attn")                var attention:              HunYuanDenseV1Attention
    @ModuleInfo(key: "mlp")                       var mlp:                   HunYuanDenseV1MLP
    @ModuleInfo(key: "input_layernorm")           var inputLayerNorm:        RMSNorm
    @ModuleInfo(key: "post_attention_layernorm")  var postAttentionLayerNorm: RMSNorm

    init(_ config: HunYuanDenseV1Configuration) {
        self._attention.wrappedValue             = HunYuanDenseV1Attention(config)
        self._mlp.wrappedValue                   = HunYuanDenseV1MLP(config)
        self._inputLayerNorm.wrappedValue        = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
        self._postAttentionLayerNorm.wrappedValue = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
    }

    func callAsFunction(
        _ x: MLXArray, mask: MLXFast.ScaledDotProductAttentionMaskMode, cache: KVCache?
    ) -> MLXArray {
        var r = attention(inputLayerNorm(x), mask: mask, cache: cache)
        let h = x + r
        r = mlp(postAttentionLayerNorm(h))
        return h + r
    }
}

// MARK: - MLP (SiLU gate, identical key names to Llama)

final class HunYuanDenseV1MLP: Module, UnaryLayer {

    @ModuleInfo(key: "gate_proj") var gate: Linear
    @ModuleInfo(key: "down_proj") var down: Linear
    @ModuleInfo(key: "up_proj")   var up:   Linear

    init(_ config: HunYuanDenseV1Configuration) {
        self._gate.wrappedValue = Linear(config.hiddenSize, config.intermediateSize, bias: config.mlpBias)
        self._down.wrappedValue = Linear(config.intermediateSize, config.hiddenSize, bias: config.mlpBias)
        self._up.wrappedValue   = Linear(config.hiddenSize, config.intermediateSize, bias: config.mlpBias)
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        down(silu(gate(x)) * up(x))
    }
}

// MARK: - Model inner

final class HunYuanDenseV1ModelInner: Module {

    @ModuleInfo(key: "embed_tokens") var embedTokens: Embedding

    let layers: [HunYuanDenseV1TransformerBlock]
    let norm: RMSNorm

    init(_ config: HunYuanDenseV1Configuration) {
        precondition(config.vocabularySize > 0)
        self._embedTokens.wrappedValue = Embedding(
            embeddingCount: config.vocabularySize, dimensions: config.hiddenSize)
        self.layers = (0 ..< config.hiddenLayers).map { _ in HunYuanDenseV1TransformerBlock(config) }
        self.norm = RMSNorm(dimensions: config.hiddenSize, eps: config.rmsNormEps)
    }

    func callAsFunction(_ inputs: MLXArray, cache: [KVCache]? = nil) -> MLXArray {
        var h = embedTokens(inputs)
        let mask = createAttentionMask(h: h, cache: cache?.first)
        for (i, layer) in layers.enumerated() {
            h = layer(h, mask: mask, cache: cache?[i])
        }
        return norm(h)
    }
}

// MARK: - Top-level model

/// LLM model for `model_type = "hunyuan_v1_dense"`.
///
/// Architecture is LLaMA with per-head QK RMSNorm and `rope_scaling.type = "dynamic"`.
/// Registered with `LLMTypeRegistry.shared` at engine load time.
final class HunYuanDenseV1Model: Module, LLMModel, KVCacheDimensionProvider {

    public let vocabularySize: Int
    public let kvHeads: [Int]

    let model: HunYuanDenseV1ModelInner

    @ModuleInfo(key: "lm_head") var lmHead: Linear?

    init(_ config: HunYuanDenseV1Configuration) {
        self.vocabularySize = config.vocabularySize
        self.kvHeads = (0 ..< config.hiddenLayers).map { _ in config.kvHeads }
        self.model = HunYuanDenseV1ModelInner(config)
        if !config.tieWordEmbeddings {
            self._lmHead.wrappedValue = Linear(config.hiddenSize, config.vocabularySize, bias: false)
        }
    }

    public func callAsFunction(_ inputs: MLXArray, cache: [KVCache]?) -> MLXArray {
        let out = model(inputs, cache: cache)
        if let lmHead { return lmHead(out) }
        return model.embedTokens.asLinear(out)
    }

    /// Strip unused precomputed rotary inverse frequencies (identical to LlamaModel).
    public func sanitize(weights: [String: MLXArray]) -> [String: MLXArray] {
        weights.filter { !$0.key.contains("self_attn.rotary_emb.inv_freq") }
    }

    // MARK: LoRAModel
    public var loraLayers: [Module] { model.layers }
}
