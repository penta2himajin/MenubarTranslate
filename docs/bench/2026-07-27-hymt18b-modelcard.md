# mbt-bench Report

**Machine:** Apple Silicon, RAM: 64 GB, macOS Version 26.5.2 (Build 25F84)
**llama.cpp pin:** b9878 | **mlx-swift-lm:** 3.31.4
**Hy-MT2 sampling:** model card (temp 0.7 / top-p 0.6)

## Summary

| Config | Cold (ms) | Warm (ms) | ΔMB | p50 | p95 | mean | chars |
|---|---|---|---|---|---|---|---|
| hymt-1.8b-mlx | 679.4 | 559.7 | 1042.1 | 398.8 | 1567.2 | 486.2 | 119.9 |

## Transcripts

### hymt-1.8b-mlx
#### JA→EN
| Source | Output |
|---|---|
| こんにちは、今日も一日頑張りましょう。 | Hello, today too, let’s try hard for one more day. |
| 今日は雨が降っていますが、明日は晴れるそうです。 | Today it’s raining, but it seems like it will be sunny tomorrow. |
| 政府は来年度の予算編成に向けた基本方針を閣議決定しました。 | The government has decided on the basic policy aimed at the preparation of the budget for the coming fiscal year. |
| この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。 | This function involves asynchronous processing by putting it into a queue. When it completes, a callback is called. |
| お世話になっております。来週の会議の日程についてご相談があります。 | Thank you for your care. We would like to discuss the agenda for next week's meeting. |
| ちょっと手伝ってくれない？後でご飯行かない？ | Could you help a little? Later, won’t we go for rice? |
| 急速に進展する人工知能技術は社会の構造そのものを変容させつつある。 | The rapidly developing technology of artificial intelligence is transforming the structure of society itself. |
| 2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。 | On July 6, 2026, I will take the Meizu No.1 from Tokyo Station to Shin-Osaka Station. |

#### EN→JA
| Source | Output |
|---|---|
| Hello, let's do our best again today. | こんにちも、今日も最善を尽くしましょう。 |
| It's raining today, but it's supposed to clear up tomorrow. | 今日は雨が降っていますが、明日は晴れるはずです。 |
| The cabinet approved the basic policy for next fiscal year's budget drafting. | 閣僚会議は、来年度の予算策定のための次年度の基本政策を承認した。 |
| This function enqueues an async task and invokes a callback on completion. | この機能は、非同期タスクを登録し、完了時にコールバックを呼び出します。 |
| I hope this message finds you well. I'd like to discuss next week's meeting schedule. | このメッセージがあなたにとって良いものであることを願っています。来週の会議のスケジュールについて話し合いたいです。 |
| Could you give me a hand? Wanna grab dinner later? | 助けてくれますか？後で夕食を食べに行きたいですか？ |
| Rapidly advancing artificial intelligence technology is transforming the very structure of society. | 急速に進歩する人工知能技術が、社会の構造そのものを変えている。 |
| On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. | 2026年7月6日、東京駅から新大阪駅まで、ノザミ第1号で移動します。 |

