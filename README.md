# magonote

個人用 AI エージェント支援ツール群。`magonote` は複数のツールを束ねる総称で、
macOS / iOS それぞれ 1 つのアプリ (どちらも「Magonote」) がツールをホストする。

最初のツールは **Magonote Reader**: Mac 上で選択したテキストをショートカット一発で
サーバーに保存し、iPhone の見やすいビューワーで読む。

システム寄りの補助アプリとして、macOS メニューバーアプリ **寝るな** もある。
MacBook の蓋を閉じてもスリープせず、codex などのプロセスを動かし続けられる。

設計の詳細は [`docs/superpowers/specs/2026-07-10-magonote-reader-design.md`](docs/superpowers/specs/2026-07-10-magonote-reader-design.md) を参照。
進捗・意思決定ログは Linear [DEV-1](https://linear.app/soprog/issue/DEV-1/magonote-reader-爆誕) 配下で管理している。

## アプリ識別子

- Firebase project: `magonote-souta0104`
- iOS Bundle ID: `app.soprog.magonote.ios`
- macOS Bundle ID: `app.soprog.magonote.macos`
- 寝るな Bundle ID: `app.soprog.magonote.neruna`

## リポジトリ構成

```
├── server/            # magonote API (TypeScript, Hono, Cloudflare Workers, D1)
├── packages/MagonoteKit/  # iOS/macOS 共有 SPM パッケージ
├── apps/ios/          # iOS アプリ「Magonote」(XcodeGen)
├── apps/macos/         # macOS アプリ「Magonote」(XcodeGen)
└── apps/neruna/        # macOS メニューバーアプリ「寝るな」(XcodeGen)
```

## セットアップ

公開リポジトリのため、以下は git 管理外 (`.gitignore` 参照) — 各自で用意すること:

- `apps/ios/GoogleService-Info.plist`
- `apps/macos/GoogleService-Info.plist`
- `server/.dev.vars`

### 前提ツール

- Node.js (npm)
- Xcode 16+ (iOS 18 / macOS 14 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Wrangler](https://developers.cloudflare.com/workers/wrangler/) (`server/` の devDependencies に含まれるため `npm install` 後は `npx wrangler` で使える)
- `sqlite3def` (`brew install sqldef/sqldef/sqlite3def`) — D1 スキーマ適用に使用

### Firebase

Firebase project `magonote-souta0104` を使用する。

1. [Firebase Console](https://console.firebase.google.com/) でこの project を開き、
   Authentication → Sign-in method → Google が有効なことを確認する。
2. project 内の iOS app (`app.soprog.magonote.ios`) と macOS app
   (`app.soprog.magonote.macos`) それぞれの `GoogleService-Info.plist` をダウンロードし、
   `apps/ios/` `apps/macos/` に配置する。

新規に project を作り直す場合は、Google プロバイダ有効化 → 上記 2 つの Bundle ID で
app を登録 → plist ダウンロード、の順で行う。

### Cloudflare

Worker `magonote-api`、D1 `magonote`、KV `FIREBASE_CERT_CACHE` は Cloudflare account
(KNOCK と共有、[DEV-9](https://linear.app/soprog/issue/DEV-9) 参照) 上に作成済みで、
`server/wrangler.jsonc` に database_id / KV id が反映されている。

1. `npx wrangler login` で同じ account にログインする。
2. `server/.dev.vars` に以下を設定する (ローカル開発用、本番の secret とは別管理):

   ```
   FIREBASE_PROJECT_ID=magonote-souta0104
   ALLOWED_UID=<自分の Firebase UID>
   ```

   `ALLOWED_UID` は Firebase Authentication でログインした自分のアカウントの UID。
   本番の同名 secret は `npx wrangler secret put ALLOWED_UID` で別途設定済み。

D1/KV を初めて作る場合は `wrangler d1 create magonote` /
`wrangler kv namespace create FIREBASE_CERT_CACHE` で作成し、出力された id を
`wrangler.jsonc` に転記する。

### Server (`server/`)

```sh
npm install
npm run db:apply:local   # ローカル D1 に schema.sql を適用
npm test                 # vitest
npm run dev              # wrangler dev (http://localhost:8787)
npm run deploy           # 本番デプロイ (wrangler deploy)
```

`npm run db:diff:remote` / `npm run db:apply:remote` で本番 D1 との差分確認・適用ができる。

### iOS / macOS アプリ (`apps/ios/`, `apps/macos/`)

各ディレクトリで以下を実行する (GoogleService-Info.plist を配置済みであること)。

```sh
cd apps/ios    # または apps/macos
xcodegen generate
open Magonote.xcodeproj
```

Xcode で Team を選択して署名し、Run する。macOS 版は初回起動時に Accessibility 権限の
許可が必要 (メニューの案内に従う)。

### 寝るな (`apps/neruna/`)

寝るながオンのあいだは、蓋を閉じてもスリープしない。
この設定はメニューバーアプリではなく root の LaunchDaemon が維持する。

```sh
cd apps/neruna
xcodegen generate
./scripts/install.sh
```

`install.sh` は Release ビルドを `/Applications/Neruna.app` に置いて起動する。
初回起動時に、蓋閉じスリープを止める helper の導入で管理者パスワードを求められる。
