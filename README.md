# magonote

個人用 AI エージェント支援ツール群。`magonote` は複数のツールを束ねる総称で、
macOS / iOS それぞれ 1 つのアプリ (どちらも「Magonote」) がツールをホストする。

最初のツールは **Magonote Reader**: Mac 上で選択したテキストをショートカット一発で
サーバーに保存し、iPhone の見やすいビューワーで読む。

設計の詳細は [`docs/superpowers/specs/2026-07-10-magonote-reader-design.md`](docs/superpowers/specs/2026-07-10-magonote-reader-design.md) を参照。
進捗・意思決定ログは Linear [DEV-1](https://linear.app/sota-hagiwara/issue/DEV-1/magonote-reader-爆誕) 配下で管理している。

## リポジトリ構成

```
├── server/            # magonote API (TypeScript, Hono, Cloudflare Workers, D1)
├── packages/MagonoteKit/  # iOS/macOS 共有 SPM パッケージ
├── apps/ios/          # iOS アプリ「Magonote」(XcodeGen)
└── apps/macos/         # macOS アプリ「Magonote」(XcodeGen)
```

## セットアップ

セットアップ手順 (Firebase プロジェクト作成、Cloudflare リソース作成、XcodeGen での
プロジェクト生成など) は各コンポーネントの実装が揃った段階でこのセクションに追記する
(Linear DEV-8 で最終化予定)。

公開リポジトリのため、以下は git 管理外 (`.gitignore` 参照) — 各自で用意すること:

- `apps/ios/GoogleService-Info.plist`
- `apps/macos/GoogleService-Info.plist`
- `server/.dev.vars`

D1 のスキーマ (`server/schema.sql`) の適用には `sqlite3def` が必要
(`brew install sqldef/sqldef/sqlite3def`)。
