# mbt-bench Report

**Machine:** Apple Silicon, RAM: 64 GB, macOS Version 26.5.2 (Build 25F84)
**llama.cpp pin:** b9878 | **mlx-swift-lm:** 3.31.4
**Hy-MT2 sampling:** greedy (MBT_SAMPLING=greedy)

## Summary

| Config | Cold (ms) | Warm (ms) | ΔMB | p50 | p95 | mean | chars |
|---|---|---|---|---|---|---|---|
| hymt-1.8b-mlx | 629.3 | 571.5 | 1043.0 | 388.0 | 656.9 | 416.7 | 143.2 |

## Transcripts

### hymt-1.8b-mlx
#### JA→EN
| Source | Output |
|---|---|
| こんにちは、今日も一日頑張りましょう。 | Hello today! Let’s try our best for another day. |
| 今日は雨が降っていますが、明日は晴れるそうです。 | Today it’s raining, but it seems like it will be sunny tomorrow. |
| 政府は来年度の予算編成に向けた基本方針を閣議決定しました。 | The government has determined the basic policy aimed at the preparation of the budget for the coming fiscal year. |
| この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。 | This function involves asynchronous processing by putting it into a queue. When it’s completed, a callback is called. |
| お世話になっております。来週の会議の日程についてご相談があります。 | Thank you for your care. We would like to discuss the agenda for next week’s meeting. |
| ちょっと手伝ってくれない？後でご飯行かない？ | Could you help me a little? Later, won’t you go for rice? |
| 急速に進展する人工知能技術は社会の構造そのものを変容させつつある。 | The rapidly developing technology of artificial intelligence is transforming the structure of society itself. |
| 2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。 | On July 6, 2026, I will travel by the Naozumi 1号 train, from Tokyo Station to Shin-Osaka Station. |

#### EN→JA
| Source | Output |
|---|---|
| Hello, let's do our best again today. | こんにち、また一層の努力をしましょう。 |
| It's raining today, but it's supposed to clear up tomorrow. | 今日は雨が降っていますが、明日は晴れるはずです。 |
| The cabinet approved the basic policy for next fiscal year's budget drafting. | 閣僚会議は、来年度の予算策定に関する来年度の基本政策を承認した。 |
| This function enqueues an async task and invokes a callback on completion. | この機能は、非同期タスクを登録し、完了時にコールバックを呼び出します。 |
| I hope this message finds you well. I'd like to discuss next week's meeting schedule. | このメッセージがあなたにとって良いものであることを願っています。来週の会議スケジュールについて話し合いたいです。 |
| Could you give me a hand? Wanna grab dinner later? | 助けてくれますか？後で夕食を食べたいですか？ |
| Rapidly advancing artificial intelligence technology is transforming the very structure of society. | 急速に進歩する人工知能技術が、社会の構造そのものを変えている。 |
| On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. | 2026年7月6日、東京ステーションから新大阪ステーションまで、ノゾミ号第1便で移動します。 |

