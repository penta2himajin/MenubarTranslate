# MenubarTranslate

> Source: README.md @ <initial-commit-sha>
>
> [English](./README.md)

**ローカル完結**の macOS メニューバー翻訳アプリ。日本語 ↔ 英語を Apple Silicon 上で
完全にオンデバイス実行する。翻訳のための通信は一切外に出ない。

## ステータス

設計初期段階。実装はまだ無い。現時点では作業規約
（[`penta2himajin/templates`](https://github.com/penta2himajin/templates) から採用）と
`docs/` 以下の設計記録のみを収める。

## 設計概要

- **モデル**: TranslateGemma-4B, GGUF `Q4_K_M`（ディスク約 2.5 GB、実行時レジデント
  約 3〜3.5 GB）。llama.cpp / Metal ランタイム上で実行。→ `docs/decisions/0001-model-selection.md`
- **メモリ目標**: まず 8 GB 統合メモリ。16 GB 以上はより緩い常駐を許容。
- **常駐**: プロセスは生かしたまま、モデルの weight だけを退避・再ロードする
  「重みレベル常駐」。Metal/ランタイム初期化を償却する。コールド再ロードは約 0.5 秒。
- **退避**: idle timeout ∨ memory pressure で駆動。8 GB は既定で退避、16 GB の常駐は opt-in。
- **thrash 無し**: 退避は pressure/timeout に、ロードはユーザー intent のみに反応する。
  この非対称性が evict↔load 振動を排除し、二重ヒステリシスで補強する。
- **`Critical` pressure 時**: lean-load＋使用後即退避に加え、capability-gated で
  Apple のオンデバイス Translation framework にフォールバック。

詳細は `docs/architecture.md`、`docs/decisions/` の ADR、未検証タスクをまとめた
`docs/validation.md` を参照。

## 規約

本リポジトリは `penta2himajin/templates` の規約に従う: SSOT は `AGENTS.md`
（`CLAUDE.md` はそのシンボリックリンク）、ADR は `docs/decisions/`、Issue ベースの
セッションハンドオフ（`docs/handoff-protocol.md`）、エンジニアリング文書は英語のみ
（`docs/i18n-policy.md`）。

## ライセンス

MIT。詳細は `LICENSE` を参照。
