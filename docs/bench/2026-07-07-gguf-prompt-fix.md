# mbt-bench Report

**Machine:** Apple Silicon, RAM: 64 GB, macOS Version 26.5.2 (Build 25F84)
**llama.cpp pin:** b9878 | **mlx-swift-lm:** 3.31.4

## Summary

| Config | Cold (ms) | Warm (ms) | ΔMB | p50 | p95 | mean | chars |
|---|---|---|---|---|---|---|---|
| gemma-mlx | 2015.1 | 1957.6 | 2268.7 | 849.9 | 1204.7 | 904.7 | 62.2 |
| hymt-1.8b-mlx | 600.9 | 605.0 | 993.4 | 395.4 | 688.9 | 435.2 | 133.8 |
| hymt-7b-mlx | 952.7 | 935.4 | 4047.2 | 641.9 | 1626.3 | 804.9 | 74.9 |
| gemma-gguf | 425.6 | 410.7 | 559.0 | 355.9 | 672.9 | 418.0 | 147.1 |
| hymt-7b-gguf | 434.4 | 428.9 | 539.8 | 612.9 | 1895.9 | 834.7 | 63.6 |

## Transcripts

### gemma-mlx
#### JA→EN
| Source | Output |
|---|---|
| こんにちは、今日も一日頑張りましょう。 | Hello, let's do our best today. |
| 今日は雨が降っていますが、明日は晴れるそうです。 | Today it's raining, but the forecast says it will be sunny tomorrow. |
| 政府は来年度の予算編成に向けた基本方針を閣議決定しました。 | The government has finalized its basic policy for budget formation for the coming fiscal year. |
| この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。 | This function puts asynchronous processing into a queue and calls a callback function when it’s completed. |
| お世話になっております。来週の会議の日程についてご相談があります。 | Hello. I wanted to discuss the schedule for next week’s meeting. |
| ちょっと手伝ってくれない？後でご飯行かない？ | Could you please lend a hand? Would you like to go out for dinner later? |
| 急速に進展する人工知能技術は社会の構造そのものを変容させつつある。 | Rapidly advancing artificial intelligence technology is fundamentally transforming the structure of society. |
| 2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。 | On July 6, 2026, I will take the Nozomi 1 train from Tokyo Station to Shin-Osaka Station. |

#### EN→JA
| Source | Output |
|---|---|
| Hello, let's do our best again today. | こんにちは。今日、できる限りのことを頑張りましょう。 |
| It's raining today, but it's supposed to clear up tomorrow. | 今日は雨ですが、明日晴れると予報です。 |
| The cabinet approved the basic policy for next fiscal year's budget drafting. | 内閣は、来年度の予算編成のための基本方針を承認しました。 |
| This function enqueues an async task and invokes a callback on completion. | この関数は、非同期タスクをキューに入れ、完了時にコールバックを呼び出す。 |
| I hope this message finds you well. I'd like to discuss next week's meeting schedule. | このメッセージを拝見いただき、お元気でお過ごしでしょうか。来週の会議のスケジュールについて、お話ししたいことがございます。 |
| Could you give me a hand? Wanna grab dinner later? | 手伝っていただけませんか？ 後で一緒に食事でもどうですか？ |
| Rapidly advancing artificial intelligence technology is transforming the very structure of society. | 急速に進歩する人工知能技術は、社会の構造そのものを変えつつあります。 |
| On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. | 2026年7月6日、私は東京駅から新大阪駅へ、のぞみ1号で移動します。 |

### hymt-1.8b-mlx
#### JA→EN
| Source | Output |
|---|---|
| こんにちは、今日も一日頑張りましょう。 | Hello today! Let’s work hard for another day. |
| 今日は雨が降っていますが、明日は晴れるそうです。 | Today it's raining, but it seems like it will be sunny tomorrow. |
| 政府は来年度の予算編成に向けた基本方針を閣議決定しました。 | The government has approved the basic policy directed towards the preparation of the budget for the coming fiscal year. |
| この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。 | This function involves asynchronous processing by putting it into a queue. When it completes, a callback is called. |
| お世話になっております。来週の会議の日程についてご相談があります。 | Thank you for your help. We would like to discuss the agenda for next week’s meeting. |
| ちょっと手伝ってくれない？後でご飯行かない？ | Could you help a little? Let’s go for rice later? |
| 急速に進展する人工知能技術は社会の構造そのものを変容させつつある。 | The rapidly developing technology of artificial intelligence is transforming the structure of society itself. |
| 2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。 | On July 6, 2026, I will travel by Naozmi 1 from Tokyo Station to Shin-Osaka Station. |

#### EN→JA
| Source | Output |
|---|---|
| Hello, let's do our best again today. | こんにちも、今日も最善を尽くしましょう。 |
| It's raining today, but it's supposed to clear up tomorrow. | 今日は雨が降っていますが、明日は晴れるはずです。 |
| The cabinet approved the basic policy for next fiscal year's budget drafting. | 内閣は、来期の予算策定のための、来期の予算に関する基本方針を承認した。 |
| This function enqueues an async task and invokes a callback on completion. | この機能は、非同期タスクを登録し、完了時にコールバックを呼び出します。 |
| I hope this message finds you well. I'd like to discuss next week's meeting schedule. | このメッセージがあなたを良い状態で過ごさせますように。来週の会議スケジュールについて話し合いたいです。 |
| Could you give me a hand? Wanna grab dinner later? | 助けてくれますか？後で夕食を食べたいですか？ |
| Rapidly advancing artificial intelligence technology is transforming the very structure of society. | 急速に進歩する人工知能技術が、社会の構造そのものを変えている。 |
| On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. | 2026年7月6日、東京ステーションから新大阪ステーションへ、初代ノザミ号で移動します。 |

### hymt-7b-mlx
#### JA→EN
| Source | Output |
|---|---|
| こんにちは、今日も一日頑張りましょう。 | Hello, let’s strive hard throughout today as well. |
| 今日は雨が降っていますが、明日は晴れるそうです。 | It's raining today, but it's supposed to be sunny tomorrow. |
| 政府は来年度の予算編成に向けた基本方針を閣議決定しました。 | The government has approved at a cabinet meeting the basic policy guidelines for formulating next fiscal year’s budget. |
| この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。 | This function queues asynchronous processing tasks, and invokes a callback when the tasks are completed. |
| お世話になっております。来週の会議の日程についてご相談があります。 | I hope this message finds you well. I would like to discuss the schedule for next week’s meeting. |
| ちょっと手伝ってくれない？後でご飯行かない？ | Could you give me a little help? How about going out for dinner later? |
| 急速に進展する人工知能技術は社会の構造そのものを変容させつつある。 | The rapidly advancing artificial intelligence technology is transforming the very structure of society. |
| 2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。 | On July 6, 2026, I will travel on Nozomi 1 from Tokyo Station to Shin-Osaka Station. |

#### EN→JA
| Source | Output |
|---|---|
| Hello, let's do our best again today. | こんにちは、今日もまた最善を尽くしましょう。 |
| It's raining today, but it's supposed to clear up tomorrow. | 今日は雨が降っていますが、明日には天気が回復する見込みです。 |
| The cabinet approved the basic policy for next fiscal year's budget drafting. | 内閣は、次の会計年度の予算編成に向けた基本方針を承認した。 |
| This function enqueues an async task and invokes a callback on completion. | この関数は、非同期タスクをキューに入れ、完了時にコールバックを呼び出します。 |
| I hope this message finds you well. I'd like to discuss next week's meeting schedule. | このメッセージが、あなたが元気でいることを知らせるものでありますように。来週の会議スケジュールについて話し合いたいと思います。 |
| Could you give me a hand? Wanna grab dinner later? | 手伝ってもらえませんか？後で一緒に夕食を食べませんか？ |
| Rapidly advancing artificial intelligence technology is transforming the very structure of society. | 急速に進化する人工知能技術は、社会の構造そのものを変革している。 |
| On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. | 2026年7月6日、私はのぞみ1号に乗り、東京駅から新大阪駅まで旅行します。 |

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

### hymt-7b-gguf
#### JA→EN
| Source | Output |
|---|---|
| こんにちは、今日も一日頑張りましょう。 | Hello, let’s do our best today as well. |
| 今日は雨が降っていますが、明日は晴れるそうです。 | It's raining today, but it's supposed to be sunny tomorrow. |
| 政府は来年度の予算編成に向けた基本方針を閣議決定しました。 | The government has approved the basic guidelines for drafting next year’s budget at a cabinet meeting. |
| この関数は非同期処理をキューに投入し、完了時にコールバックを呼ぶ。 | This function queues asynchronous tasks and calls a callback when they are completed. |
| お世話になっております。来週の会議の日程についてご相談があります。 | Hello. I would like to discuss the schedule for next week’s meeting. |
| ちょっと手伝ってくれない？後でご飯行かない？ | Could you give me a hand? Want to go eat later? |
| 急速に進展する人工知能技術は社会の構造そのものを変容させつつある。 | The rapidly advancing artificial intelligence technology is transforming the very structure of society. |
| 2026年7月6日、東京駅から新大阪駅までのぞみ1号で向かいます。 | On July 6, 2026, I will travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. |

#### EN→JA
| Source | Output |
|---|---|
| Hello, let's do our best again today. | こんにちは、今日も全力を尽くしましょう。 |
| It's raining today, but it's supposed to clear up tomorrow. | 今日は雨が降っていますが、明日には晴れる見込みです。 |
| The cabinet approved the basic policy for next fiscal year's budget drafting. | 内は、来年度の予算編成に向けた基本方針を承認した。 |
| This function enqueues an async task and invokes a callback on completion. | この関数は非同期タスクをキューに投入し、完了時にコールバックを呼び出します。 |
| I hope this message finds you well. I'd like to discuss next week's meeting schedule. | このメッセージが届いた時には、お元気でいらっしゃることを願っています。来週の会議のスケジュールについて話し合いたいと思います。 |
| Could you give me a hand? Wanna grab dinner later? | 手伝ってもらえますか？後で一緒に夕食を食べませんか？ |
| Rapidly advancing artificial intelligence technology is transforming the very structure of society. | 急速に進化する人工知能技術が、社会の構造そのものを変えつつある。 |
| On July 6, 2026, I'll travel from Tokyo Station to Shin-Osaka Station on Nozomi No. 1. | 2026年7月6日、ノミ1号で東京から新大阪へ向かいます。 |

