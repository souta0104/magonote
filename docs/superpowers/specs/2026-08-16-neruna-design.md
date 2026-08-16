# 寝るな (Neruna)

MacBook の蓋を閉じてもプロセスを動かし続けるための macOS メニューバーアプリ。

## Context

magonote は個人用 AI エージェント支援ツール群である。codex などの長時間プロセスを、MacBook Air の蓋を閉じたまま動かしたい。

IOKit の sleep assertion や `caffeinate` はアイドル時のスリープしか止められない。蓋を閉じたときのスリープを止めるには、`pmset disablesleep` が必要である。この値は電源ソース別ではなく、システム全体に効く。

## 合意

- アプリ名は「寝るな」、バンドルは `Neruna.app`、Bundle ID は `app.soprog.magonote.neruna`
- Magonote 本体には入れない。認証も API もなく、起動寿命も権限モデルも Reader と異なるため、独立した macOS アプリにする
- 寝るながオンなら、電源の有無に関係なく蓋を閉じてもスリープしない
- 電池残量が設定値を下回ったらスリープする。初期値は 15%。電源接続中は見ない
- オンにしてから設定時間がたったらスリープし、寝るなをオフにする。初期値は制限なし
- `pmset disablesleep` はメニューバーアプリではなく、root の LaunchDaemon が維持する
- ログイン時に起動する。初回起動時は「寝るな」をオンにする

## ユビキタス言語

| 概念 | 定義 | コード | UI |
|---|---|---|---|
| 寝るな | 蓋を閉じてもスリープしないようにする機能全体 | `Neruna` | 寝るな |
| Desired awake | 利用者が「起きていてほしい」と望んでいるか | `DesiredAwakeState` | オン / オフ |
| Lid-close sleep | 蓋を閉じたときにシステムがスリープすること | `shouldKeepAwakeWithLidClosed` | 蓋を閉じても起きている |
| Idle sleep | 操作がないときにシステムがスリープすること | `shouldPreventIdleSleep` | (メニューには出さない) |
| Helper | `pmset` を root で実行するコマンド | `neruna-helper` | (出さない) |
| Battery guard | 電池残量が設定値未満ならスリープする条件 | `batteryThresholdPercent` | 電池が n% を下回ったら寝る |
| Duration guard | オンにしてから設定時間がたったらスリープする条件 | `durationLimitSeconds` | n 時間たったら寝る |

「スリープ防止」「カフェイン」「アサーション」などの別名は UI に出さない。

## 構成

```
apps/neruna/
├── NerunaCore/          # 判定とコマンド組み立て。アプリ・helper・テストが共有する
├── NerunaHelper/        # root で動く CLI / LaunchDaemon
├── Neruna/              # メニューバーアプリ
├── NerunaTests/
├── launchd/             # LaunchDaemon plist と sudoers
└── scripts/             # ビルドとこのマシンへのインストール
```

### NerunaCore

`SleepPreventionPolicy` が唯一の判定表である。

- 寝るながオンで、電池ガードも時間ガードも満たさない → 起き続ける
- 電池が設定値未満、または時間切れ → `pmset sleepnow` し、蓋閉じスリープも許可する
- 時間切れは desired を off にする。電池ガードは充電が戻るまで latch し、desired は on のまま
- 電池ガードの復帰は、設定値 + 5% を超えたとき、または電源接続時

### neruna-helper

| 引数 | 誰が呼ぶか | すること |
|---|---|---|
| `apply-on` | アプリが `sudo -n` で呼ぶ。stdin に JSON を渡す | 設定を書き、policy を適用する |
| `apply-off` | アプリが `sudo -n` で呼ぶ。stdin に JSON を渡す | 設定を書き、policy を適用する |
| `status` | アプリが `sudo -n` で呼ぶ | desired / reason / 電池 / SleepDisabled を出す |
| `run` | LaunchDaemon だけ | 起動時と 5 秒ごとの確認で policy を再適用する |

LaunchDaemon はアプリが死んでいても、同じ判定表で `disablesleep` を維持し、ガード成立時はスリープする。

### メニューバーアプリ

- `LSUIElement` の MenuBarExtra
- オン/オフ、今の状態、電池ガード、時間ガード、設定、ログイン時に起動、終了
- 終了するときは desired を off にする
- アイドル睡眠は IOKit assertion で止める。root は不要
- helper が未導入なら、管理者パスワードを 1 回求めて導入する

## 入れないもの

- 外部ディスプレイ前提のクラムシェルモード
- プロセス名を指定して起きる機能
- Magonote へのログインや Reader 連携
