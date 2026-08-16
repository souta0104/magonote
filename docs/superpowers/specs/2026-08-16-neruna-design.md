# 寝るな (Neruna)

MacBook の蓋を閉じても、電源接続中はプロセスを動かし続けるための macOS メニューバーアプリ。

## Context

magonote は個人用 AI エージェント支援ツール群である。codex などの長時間プロセスを、MacBook Air の蓋を閉じたまま動かしたい。

IOKit の sleep assertion や `caffeinate` はアイドル時のスリープしか止められない。蓋を閉じたときのスリープを止めるには、`pmset disablesleep` が必要である。この値は電源ソース別ではなく、システム全体に効く。

## 合意

- アプリ名は「寝るな」、バンドルは `Neruna.app`、Bundle ID は `app.soprog.magonote.neruna`
- Magonote 本体には入れない。認証も API もなく、起動寿命も権限モデルも Reader と異なるため、独立した macOS アプリにする
- 蓋を閉じたまま起き続けるのは電源接続中だけにする。電池では蓋を閉じたらスリープする
- その安全条件はメニューバーアプリではなく、root の LaunchDaemon が守る
- ログイン時に起動する。初回起動時は「寝るな」をオンにする

## ユビキタス言語

| 概念 | 定義 | コード | UI |
|---|---|---|---|
| 寝るな | 蓋を閉じても、電源接続中はスリープしないようにする機能全体 | `Neruna` | 寝るな |
| Desired awake | 利用者が「起きていてほしい」と望んでいるか | `DesiredAwakeState` | オン / オフ |
| Lid-close sleep | 蓋を閉じたときにシステムがスリープすること | `shouldKeepAwakeWithLidClosed` | 蓋を閉じても起きている |
| Idle sleep | 操作がないときにシステムがスリープすること | `shouldPreventIdleSleep` | (メニューには出さない) |
| Helper | `pmset` を root で実行するコマンド | `neruna-helper` | (出さない) |

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

- 寝るながオン、かつ電源接続中 → `pmset -a disablesleep 1`
- それ以外 → `pmset -a disablesleep 0`
- 寝るながオン → アプリが IOKit の `PreventUserIdleSystemSleep` を取る

### neruna-helper

| 引数 | 誰が呼ぶか | すること |
|---|---|---|
| `apply-on` | アプリが `sudo -n` で呼ぶ | desired を on にし、今の電源で `pmset` を合わせる |
| `apply-off` | アプリが `sudo -n` で呼ぶ | desired を off にし、`disablesleep 0` にする |
| `status` | アプリが `sudo -n` で呼ぶ | desired / 電源 / SleepDisabled を出す |
| `run` | LaunchDaemon だけ | 起動時・電源変化・定期確認で policy を再適用する |

LaunchDaemon はアプリが死んでいても、電池になったら `disablesleep 0` に戻す。

### メニューバーアプリ

- `LSUIElement` の MenuBarExtra
- オン/オフ、今の状態、ログイン時に起動、終了
- 終了するときは desired を off にする
- アイドル睡眠は IOKit assertion で止める。root は不要
- helper が未導入なら、管理者パスワードを 1 回求めて導入する

## 入れないもの

- 電池でも蓋を閉じたまま起き続けるオプション
- 外部ディスプレイ前提のクラムシェルモード
- 指定時間だけ起きるタイマー
- プロセス名を指定して起きる機能
- Magonote へのログインや Reader 連携
