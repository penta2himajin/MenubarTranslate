# mbt-bench Report

**Machine:** Apple Silicon, RAM: 64 GB, macOS Version 26.5.2 (Build 25F84)
**llama.cpp pin:** b9878 | **mlx-swift-lm:** 3.31.4
**Hy-MT2 sampling:** model card (temp 0.7 / top-p 0.6)

## Summary

| Config | Cold (ms) | Warm (ms) | ΔMB | p50 | p95 | mean | chars |
|---|---|---|---|---|---|---|---|
| milmmt-1b-mlx | 2034.0 | 2071.4 | 887.1 | 269.2 | 920.2 | 320.9 | 153.3 |

## Transcripts

### milmmt-1b-mlx
#### JA→EN
| Source | Output |
|---|---|
| こんにちは、今日も一日頑張りましょう。 | Hello, let's do our best today. |
| 今日は雨が降っていますが、明日は晴れるそうです。 | Today it is raining, but tomorrow it will be sunny. |
| 政府は来年度の予算編成に向けた基本方針を閣議決定しました。 | The government has decided on a basic policy for the fiscal 2022 budget. |
| この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。 | This function puts a asynchronous process into a queue and calls a callback when it completes. |
| お世話になっております。来週の会議の日程についてご相談があります。 | I have a question regarding the schedule of my meeting next week. |
| ちょっと手伝ってくれない？後でご飯行かない？ | Do you want to help a little? Don’t you want to have a meal together later? |
| 急速に進展する人工知能技術は社会の構造そのものを変容させつつある。 | Rapid advances in artificial intelligence are transforming the very fabric of society. |
| 2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。 | On July 6, 2026, we will take the Shinkansen from Tokyo Station to Shin-Osaka Station. |

#### EN→JA
| Source | Output |
|---|---|
| Hello, let's do our best again today. | こんにちは、今日はもう一度最善を尽くしましょう。 |
| It's raining today, but it's supposed to clear up tomorrow. | 今日は雨ですが、明日には晴れそうです。 |
| The cabinet approved the basic policy for next fiscal year's budget drafting. | 閣議会は、来年度の予算策定の基本方針を承認した。 |
| This function enqueues an async task and invokes a callback on completion. | この関数は無動作タスクをエスケープして、完了時にコールバックを呼び出します。 |
| I hope this message finds you well. I'd like to discuss next week's meeting schedule. | 今週のご挨拶。来週の会議の予定についてお話ししたいと思います。 |
| Could you give me a hand? Wanna grab dinner later? | お手伝いしてくれる？ 夕食は一緒に食べようか？ |
| Rapidly advancing artificial intelligence technology is transforming the very structure of society. | 急速に進歩する人工知能技術は、社会の構造を根本から変えています。 |
| On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. | 2026年7月6日、私はノズミ1号で東京駅から新大阪駅までお越しします。 |

