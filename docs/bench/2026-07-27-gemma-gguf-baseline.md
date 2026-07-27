# mbt-bench Report

**Machine:** Apple Silicon, RAM: 64 GB, macOS Version 26.5.2 (Build 25F84)
**llama.cpp pin:** b9878 | **mlx-swift-lm:** 3.31.4
**Hy-MT2 sampling:** model card (temp 0.7 / top-p 0.6)

## Summary

| Config | Cold (ms) | Warm (ms) | ΔMB | p50 | p95 | mean | chars |
|---|---|---|---|---|---|---|---|
| gemma-gguf | 448.2 | 447.0 | 602.2 | 769.8 | 1290.8 | 814.8 | 75.5 |

## Transcripts

### gemma-gguf
#### JA→EN
| Source | Output |
|---|---|
| こんにちは、今日も一日頑張りましょう。 | Hello, let's have a productive day today. |
| 今日は雨が降っていますが、明日は晴れるそうです。 | It's raining today, but the forecast says it will be sunny tomorrow. |
| 政府は来年度の予算編成に向けた基本方針を閣議決定しました。 | The government has approved a basic policy for the budget formulation for the upcoming fiscal year. |
| この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。 | This function places the asynchronous operation in a queue and calls the callback function when the operation is complete. |
| お世話になっております。来週の会議の日程についてご相談があります。 | Thank you for your continued support. I would like to discuss the schedule for the upcoming meeting. |
| ちょっと手伝ってくれない？後でご飯行かない？ | Could you possibly lend me a hand? Would you be free to go out for dinner later? |
| 急速に進展する人工知能技術は社会の構造そのものを変容させつつある。 | The rapidly advancing field of artificial intelligence is transforming the very fabric of society. |
| 2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。 | On July 6, 2026, I will travel from Tokyo Station to Shin-Osaka Station on the Nozomi 1 train. |

#### EN→JA
| Source | Output |
|---|---|
| Hello, let's do our best again today. | 皆さん、今日は一日、できる限りの努力をしましょう。 |
| It's raining today, but it's supposed to clear up tomorrow. | 今日は雨ですが、明日は晴れると予想されています。 |
| The cabinet approved the basic policy for next fiscal year's budget drafting. | 内閣は、次年度の予算編成のための基本方針を承認しました。 |
| This function enqueues an async task and invokes a callback on completion. | この関数は、非同期タスクをキューに入れ、タスクの完了時にコールバック関数を呼び出します。 |
| I hope this message finds you well. I'd like to discuss next week's meeting schedule. | このメッセージが皆様にお届けできることを願っています。来週の会議のスケジュールについて、ご相談させて頂きたいです。 |
| Could you give me a hand? Wanna grab dinner later? | 何か手伝っていただけませんか？ 今夜、一緒に夕食でもどうですか？ |
| Rapidly advancing artificial intelligence technology is transforming the very structure of society. | 急速に進歩している人工知能技術は、社会の構造そのものを変えつつあります。 |
| On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. | 2026年7月6日、私は東京駅から新大阪駅まで、ノゾミ1号に乗車します。 |

