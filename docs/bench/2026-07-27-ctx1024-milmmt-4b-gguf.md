# mbt-bench Report

**Machine:** Apple Silicon, RAM: 64 GB, macOS Version 26.5.2 (Build 25F84)
**llama.cpp pin:** b9878 | **mlx-swift-lm:** 3.31.4
**llama.cpp n_ctx:** 1024
**Hy-MT2 sampling:** model card (temp 0.7 / top-p 0.6)

## Summary

| Config | Cold (ms) | Warm (ms) | ΔMB | p50 | p95 | mean | chars |
|---|---|---|---|---|---|---|---|
| milmmt-4b-gguf | 365.8 | 366.4 | 194.1 | 265.3 | 487.0 | 289.4 | 174.9 |

## Transcripts

### milmmt-4b-gguf
#### JA→EN
| Source | Output |
|---|---|
| こんにちは、今日も一日頑張りましょう。 | Hello, let's work hard today. |
| 今日は雨が降っていますが、明日は晴れるそうです。 | It's raining today, but it's supposed to be sunny tomorrow. |
| 政府は来年度の予算編成に向けた基本方針を閣議決定しました。 | The government has decided on the basic policy for next year's budget. |
| この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。 | This function queues the asynchronous process and calls a callback when it is completed. |
| お世話になっております。来週の会議の日程についてご相談があります。 | I'd like to ask about the schedule for next week's meeting. |
| ちょっと手伝ってくれない？後でご飯行かない？ | Can you help me with something? Want to go out for dinner later? |
| 急速に進展する人工知能技術は社会の構造そのものを変容させつつある。 | Artificial intelligence technology is rapidly advancing, transforming the very structure of society. |
| 2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。 | On July 6, 2026, I will be traveling on the Nozomi 1 train from Tokyo Station to Shin-Osaka Station. |

#### EN→JA
| Source | Output |
|---|---|
| Hello, let's do our best again today. | こんにちは、今日はまた頑張りましょう。 |
| It's raining today, but it's supposed to clear up tomorrow. | 今日は雨が降っていますが、明日は晴れるそうです。 |
| The cabinet approved the basic policy for next fiscal year's budget drafting. | 内閣は、来年度の予算編成の基本方針を承認した。 |
| This function enqueues an async task and invokes a callback on completion. | この関数は非同期タスクをキューに入れ、完了時にコールバックを呼び出します。 |
| I hope this message finds you well. I'd like to discuss next week's meeting schedule. | このメッセージが届いていれば幸いです。来週のミーティングのスケジュールについて相談したいです。 |
| Could you give me a hand? Wanna grab dinner later? | 手伝ってくれませんか？後で夕飯でもどうですか？ |
| Rapidly advancing artificial intelligence technology is transforming the very structure of society. | 急速に進歩する人工知能技術は、社会の構造そのものを変えている。 |
| On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. | 2026年7月6日、私は東京駅から新大阪駅まで「のぞみ1号」に乗車します。 |

