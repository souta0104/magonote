# magonote / Magonote Reader 設計

進捗・意思決定ログは Linear [DEV-1](https://linear.app/sota-hagiwara/issue/DEV-1/magonote-reader-爆誕) 配下の sub issue で管理する。本ドキュメントは技術設計の正典。

## Context

個人用 AI エージェント支援ツール群「magonote」のモノレポを新規構築する。
magonote はツール群の総称で、アプリはプラットフォームごとに 1 つ (macOS「Magonote」/ iOS「Magonote」)。
ツールは今後どんどん増える前提で、各アプリの中に複数ツールが同居する。

最初のツールは「Magonote Reader」(スマホでドキュメントを見れるくん)。
Mac 上で選択したテキストをショートカット一発でサーバーに保存し、iPhone の見やすい
ビューワーで読む。AI の出力をシュッとスマホに移して読むのがモチベ。
リポジトリは public、利用者は自分 1 人のみ。

合意済みの決定:

- 命名: 総称 magonote / アプリ名 Magonote (mac, ios) / 今回のツールは Reader。
  ツール追加に備えて API ルート・D1 テーブル・アプリ内フォルダはツール名で名前空間を切る
- 選択テキスト取得: 最前面アプリへ Cmd+C を送信し、general pasteboard に書き込まれた
  文字列を取得。取得した文字列は pasteboard に残し、開始前の内容へ復元しない
- コメントのアンカー: 引用テキスト方式 (選択文字列をコメントに quote として保存。オフセット保存やハイライトはしない)
- プロジェクト管理: XcodeGen (xcodeproj は git-ignore)
- Firebase プロジェクトは新規作成、Cloudflare はアカウントあり・wrangler 未ログイン
- bundle id: app.soprog.magonote.ios / app.soprog.magonote.macos

## 技術方針

- iOS 18+ (TextEditor の selection binding で引用選択 UI を pure SwiftUI で作るため) / macOS 14+ / Swift 6
- backend: TypeScript + Hono + Cloudflare Workers + D1。wrangler.jsonc + `wrangler types`
- 認証: Firebase Auth (Google ログイン)。Workers 側は firebase-auth-cloudflare-workers で ID token 検証し、
  UID が secret ALLOWED_UID と一致するリクエストのみ許可 (それ以外 403)
- timestamp は unix ms (INTEGER) で統一
- public リポジトリなので GoogleService-Info.plist / .dev.vars / xcodeproj は git-ignore。
  database_id, KV id, Firebase project ID, REVERSED_CLIENT_ID は識別子であり秘密ではないためコミット可 (README に明記)

## ユビキタス言語 (用語集)

1 概念 1 用語。D1 カラム / JSON キー / Swift 型・プロパティ / UI 表示の全レイヤーで
この対応表に従い、同義語を作らない。実装時の命名判断はすべてこの表を正とする。

| 概念 | 定義 | D1 | JSON | Swift | UI 表示 |
|---|---|---|---|---|---|
| Tool | magonote を構成する個々のツール。今回は Reader | テーブル prefix `reader_` | path prefix `/api/reader` | `Tools/Reader/`, `Reader/` | Reader |
| Document | キャプチャされたテキスト本体 (Reader の中心概念) | `reader_documents` | `document` | `Document` | ドキュメント |
| Capture | Mac 上で選択テキストから Document を作る行為 | — | — | `CaptureController`, `readerCapture` | キャプチャ |
| Source | Capture が行われた場所 (アプリ + マシン) | `source_app_name`, `source_machine_name` | `sourceAppName`, `sourceMachineName` | `sourceAppName`, `sourceMachineName` | 取得元 |
| Preview | 一覧用の本文先頭 300 文字 | — (SQL substr で算出) | `preview` | `preview` | (本文の抜粋として表示) |
| Comment | Document への平坦なコメント (スレッド・返信なし) | `reader_comments` | `comment` | `Comment` | コメント |
| Quote | Comment に添付する本文からの引用文字列 | `quote` | `quote` | `quote` | 引用 |
| Archive / Unarchive | 非表示化とその解除。削除はしない | `archived_at` (NULL = Active) | `archivedAt`, `/archive`, `/unarchive` | `archivedAt`, `archive()`, `unarchive()` | アーカイブ / アーカイブ解除 |
| Active / Archived | Document・Comment の 2 状態 | `archived_at IS NULL / NOT NULL` | `filter=active\|archived` | `DocumentFilter.active/.archived` | 受信箱 / アーカイブ済み |
| capturedAt / createdAt | Capture 時のクライアント時刻 / サーバー保存時刻 | `captured_at`, `created_at` | `capturedAt`, `createdAt` | `capturedAt`, `createdAt` | 日時表示は capturedAt を使う |

- 「削除」「クリップ」「メモ」「スニペット」等の類義語は仕様・コード・UI いずれにも登場させない
- 新ツール追加時は、そのツールの用語集を先に定義してから実装する

## 設計原則

一般原則に依拠し、設計のどこに現れるかを明示する。実装時もこれを判断基準にする。

- 単一責任 (SRP): server は auth / db / tools/reader(routes・schemas) を分離。
  iOS は Store (状態と操作) と View (表示) を分離。CaptureController はキャプチャ行為のみを持ち、
  通信は MagonoteAPIClient に委譲
- 依存性逆転 (DIP): 認証は `TokenVerifier` interface (server) と `AuthTokenProvider` protocol
  (Swift) に依存し、Firebase 実装は端に置く。テストはスタブ差し替えのみで成立
- 境界での検証 (fail fast): 外部入力は zod で境界 (route) で全検証し、内部は検証済みの型のみを流す。
  Swift 側は Codable + Swift 6 strict concurrency で型不整合をコンパイル時に排除
- 情報隠蔽・カプセル化: cursor は base64url の不透明トークンとしてクライアントに内部構造を漏らさない。
  500 エラーで内部メッセージを返さない
- DRY: DTO・API 呼び出し・エラーマッピングは MagonoteKit に一本化し、iOS/macOS で重複させない。
  エラー envelope も 1 形式のみ
- YAGNI: ORM なし、router 抽象なし、ツール切替 UI なし (ツールが 2 つになるまで作らない)、
  コメントのスレッド・返信なし
- 開放閉鎖 (OCP) 的な拡張点: ツール追加 = `tools/<name>/` + `app.route()` 1 行 +
  `Tools/<name>/` + MagonoteKit extension。既存コードの変更なしで増やせる構造にする
- 冪等性: archive / unarchive は何度呼んでも同じ結果 (安全なリトライ)

## リポジトリ構成

```
├── README.md                      # セットアップガイド (Firebase / Cloudflare / XcodeGen)
├── .gitignore
├── docs/superpowers/specs/        # 本設計ドキュメント
├── server/                        # magonote API (全ツール共通の 1 Worker)
│   ├── wrangler.jsonc             # d1 binding: DB, kv binding: FIREBASE_CERT_CACHE, vars: FIREBASE_PROJECT_ID
│   ├── package.json / tsconfig.json / vitest.config.ts
│   ├── schema.sql                 # D1 スキーマの正 (sqlite3def で宣言的に適用)
│   ├── scripts/                   # sqlite3def 適用スクリプト (db-apply.sh)
│   ├── src/
│   │   ├── index.ts               # createApp(realVerifier) を export
│   │   ├── app.ts                 # createApp(deps) ファクトリ (テストの唯一の seam)
│   │   ├── auth.ts                # TokenVerifier interface + Firebase 実装 + auth middleware
│   │   ├── errors.ts              # ApiError class + ErrorCode + 生成ヘルパー
│   │   ├── db.ts                  # D1 prepared statement ヘルパー (ORM なし)
│   │   └── tools/reader/          # ツールごとに名前空間を切る (次ツールは tools/<name>/)
│   │       ├── routes.ts          # documents + comments のルート (/api/reader 配下に mount)
│   │       └── schemas.ts         # zod スキーマ
│   └── test/                      # auth / reader-documents / reader-comments
├── packages/MagonoteKit/          # 共有 SPM パッケージ (依存ゼロ、Foundation のみ)
│   ├── Package.swift              # iOS 18 / macOS 14, swift-tools 6.0
│   ├── Sources/MagonoteKit/
│   │   ├── Core/                  # MagonoteAPIClient, AuthTokenProvider, APIError, JSON coding
│   │   └── Reader/                # Document, DocumentSummary, Comment, DocumentPage, NewDocument
│   └── Tests/MagonoteKitTests/    # URLProtocol スタブテスト
└── apps/
    ├── ios/                       # iOS アプリ「Magonote」
    │   ├── project.yml
    │   ├── Magonote/
    │   │   ├── MagonoteApp.swift
    │   │   ├── Session/           # SessionStore, LoginView
    │   │   ├── Support/           # APIClientFactory など
    │   │   └── Tools/Reader/      # DocumentList / DocumentDetail / Comments / QuoteSelection / MarkdownTheme
    │   └── GoogleService-Info.plist   # git-ignore (ユーザーが配置)
    └── macos/                     # macOS アプリ「Magonote」(menu bar 常駐、全ツールのホスト)
        ├── project.yml
        ├── Magonote/
        │   ├── MagonoteApp.swift  # MenuBarExtra + Settings シーン
        │   ├── Session/           # SessionStore (Firebase/GoogleSignIn)
        │   ├── SettingsView.swift # アカウント / 権限 / サーバー URL / ツールごとの設定セクション
        │   ├── Magonote.entitlements
        │   └── Tools/Reader/      # CaptureController (hotkey → Accessibility → POST)
        └── GoogleService-Info.plist   # git-ignore
```

## D1 スキーマ (server/schema.sql)

テーブルはツール名 prefix で名前空間を切る (次ツールは同じ schema.sql に `<tool>_...` を追加)。
schema.sql が D1 スキーマの正 (source of truth) であり、sqlite3def で宣言的に適用する
(wrangler 自体の migrations の仕組みは使わない)。

```sql
CREATE TABLE reader_documents (
  id                  TEXT PRIMARY KEY,   -- crypto.randomUUID()、サーバー生成
  "text"              TEXT NOT NULL,      -- sqlite3def v3.11.13 の型キーワードとの列名衝突回避のため quote 必須
  source_app_name     TEXT NOT NULL,      -- Capture 時の最前面アプリ (Source)
  source_machine_name TEXT NOT NULL,      -- hostname (Source)
  captured_at         INTEGER NOT NULL,   -- unix ms、クライアント時刻
  created_at          INTEGER NOT NULL,   -- unix ms、サーバー時刻
  archived_at         INTEGER             -- NULL = Active
);
CREATE INDEX idx_reader_documents_active_list
  ON reader_documents (created_at DESC, id) WHERE archived_at IS NULL;
CREATE INDEX idx_reader_documents_archived_list
  ON reader_documents (created_at DESC, id) WHERE archived_at IS NOT NULL;

CREATE TABLE reader_comments (
  id           TEXT PRIMARY KEY,
  document_id  TEXT NOT NULL REFERENCES reader_documents(id),
  body         TEXT NOT NULL,
  quote        TEXT,               -- 引用文字列 (任意)
  created_at   INTEGER NOT NULL,
  archived_at  INTEGER
);
CREATE INDEX idx_reader_comments_active_by_document
  ON reader_comments (document_id, created_at ASC) WHERE archived_at IS NULL;
```

適用フロー (`server/scripts/db-apply.sh`、`sqlite3def` (Homebrew: `sqldef/sqldef/sqlite3def`) が必要):

- ローカル: ローカル D1 の実 sqlite ファイルに対する現行スキーマを `wrangler d1 export --local --no-data`
  で取得し、sqlite3def のオフライン diff モード (`sqlite3def current.sql --file schema.sql`) で
  差分 DDL を生成、`wrangler d1 execute --local` で適用する (`npm run db:apply:local`)
- リモート: 同様に `wrangler d1 export --remote --no-data` → オフライン diff → `wrangler d1 execute
  --remote` で適用する (`npm run db:diff:remote` で差分確認のみ、`npm run db:apply:remote` で適用)
- wrangler 自体の migrations 機能 (`wrangler d1 migrations apply`) は使わない

## REST API

ツールごとに `/api/<tool>` で名前空間を切る。Reader は `/api/reader` 配下。
`Authorization: Bearer <Firebase ID token>` 必須 (health を除く)。
エラーは `{ "error": { "code": "...", "message": "..." } }` (401/403/404/400/500)。

| Method & path | 用途 | Request / Response |
|---|---|---|
| POST /api/reader/documents | Mac から作成 | { text, sourceAppName, sourceMachineName, capturedAt } → 201 Document |
| GET /api/reader/documents?filter=active\|archived&limit=30&cursor= | 一覧 (新しい順) | 200 { documents: [DocumentSummary], nextCursor } |
| GET /api/reader/documents/:id | 詳細 | 200 Document |
| POST /api/reader/documents/:id/archive, /unarchive | アーカイブ切替 (冪等) | 200 Document |
| GET /api/reader/documents/:id/comments?includeArchived= | コメント一覧 (古い順、pagination なし) | 200 { comments } |
| POST /api/reader/documents/:id/comments | コメント作成 | { body, quote? } → 201 Comment |
| POST /api/reader/comments/:id/archive, /unarchive | コメントのアーカイブ切替 | 200 Comment |
| GET /api/health | 認証なし liveness | 200 { ok: true } |

- DocumentSummary は text の代わりに preview (SQL の substr で先頭 300 文字)
- Pagination は keyset 方式。cursor = base64url(JSON({ createdAt, id }))、
  `WHERE (created_at, id) < (?, ?) ORDER BY created_at DESC, id DESC LIMIT ?+1` で limit+1 件取得して nextCursor を判定
- JSON は camelCase、日時は unix ms

## Backend 実装

npm パッケージ: hono, zod, @hono/zod-validator, firebase-auth-cloudflare-workers (Code-Hex 製)。
dev: wrangler v4, vitest, @cloudflare/vitest-pool-workers, typescript。

firebase-auth-cloudflare-workers を選ぶ理由: Workers 向け専用・依存ゼロ・WebCrypto ネイティブで、
iss/aud/exp/auth_time/sub/alg/kid の Firebase 固有チェックと Google 証明書ローテーションの
max-age キャッシュを実装済み。cert キャッシュに KV namespace (binding: FIREBASE_CERT_CACHE) を使う。

### ファイル別の責務とシグネチャ

- errors.ts (db.ts と routes から使うので独立ファイルにする):
  - `class ApiError extends Error { constructor(readonly status: number, readonly code: ErrorCode, message: string) }`
  - `type ErrorCode = 'unauthorized' | 'forbidden' | 'not_found' | 'validation_error' | 'internal'`
  - `notFound(resource: string): ApiError` などの生成ヘルパー
- auth.ts:
  - `interface TokenVerifier { verify(jwt: string): Promise<{ uid: string }> }`
  - `class FirebaseTokenVerifier implements TokenVerifier` —
    `Auth.getOrInitialize(env.FIREBASE_PROJECT_ID, WorkersKVStoreSingle.getOrInitialize('firebase-certs', env.FIREBASE_CERT_CACHE)).verifyIdToken(jwt)` の薄い wrapper
  - `authMiddleware(makeVerifier): MiddlewareHandler` — Authorization ヘッダから `Bearer ` prefix を
    strip (欠落・不正形式 → 401 unauthorized) → verify (throw → 401) → `uid !== env.ALLOWED_UID` → 403 forbidden →
    成功時は `c.set('uid', uid)` して next
- db.ts: 全関数 `(db: D1Database, ...) => Promise<...>` の純粋なデータアクセス層。
  Row 型 (snake_case、D1 の生の形) と API 型 (camelCase) をここで分離し、`toDocument(row)` /
  `toDocumentSummary(row)` / `toComment(row)` の serializer で変換する
  - `insertDocument(db, input: { text, sourceAppName, sourceMachineName, capturedAt }): Promise<Document>` —
    id は crypto.randomUUID()、createdAt は Date.now() をここで採番
  - `listDocuments(db, opts: { filter, limit, cursor?: { createdAt, id } }): Promise<{ documents: DocumentSummary[], nextCursor: string | null }>` —
    limit+1 件 fetch、preview は SQL の `substr(text, 1, 300)`
  - `getDocument(db, id): Promise<Document | null>`
  - `setDocumentArchived(db, id, archivedAt: number | null): Promise<Document | null>` —
    `UPDATE ... RETURNING *` で 1 クエリで更新後の行を返す (get→update→get の 3 クエリにしない)。
    冪等 (既に同状態でも 200)
  - `insertComment(db, documentId, input: { body, quote? }): Promise<Comment>` —
    事前に document の存在チェック (なければ null を返し route が 404)
  - `listComments(db, documentId, includeArchived: boolean): Promise<Comment[] | null>` —
    document が存在しなければ null (`insertComment` と同じパターンで route が 404)
  - `setCommentArchived(db, id, archivedAt: number | null): Promise<Comment | null>` —
    `setDocumentArchived` と同様 `UPDATE ... RETURNING *` で 1 クエリ化
- tools/reader/schemas.ts (zod、境界での検証を全部ここに集約):
  - `createDocumentSchema = z.object({ text: z.string().min(1).max(500_000), sourceAppName: z.string().min(1).max(200), sourceMachineName: z.string().min(1).max(200), capturedAt: z.number().int().positive() })`
  - `listDocumentsQuerySchema = z.object({ filter: z.enum(['active','archived']).default('active'), limit: z.coerce.number().int().min(1).max(100).default(30), cursor: z.string().optional() })`
  - `createCommentSchema = z.object({ body: z.string().min(1).max(10_000), quote: z.string().min(1).max(10_000).optional() })`
  - `listCommentsQuerySchema = z.object({ includeArchived: z.enum(['true','false']).default('false').transform(v => v === 'true') })`
  - cursor ヘルパー: `encodeCursor({ createdAt, id })` = base64url(JSON)、
    `decodeCursor(s)` は parse 失敗時に `ApiError(400, 'validation_error', 'invalid cursor')` を throw
- tools/reader/routes.ts: `new Hono<Env>()` の sub-app。各 handler は
  `zValidator('json' | 'query', schema)` → db 関数呼び出し → null なら `throw notFound(...)` → JSON 返却
  のみで、ビジネスロジックを持たない (SRP)
- app.ts: `createApp(makeVerifier: (env: Env) => TokenVerifier): Hono<Env>` —
  `/api/health` 登録 → `app.use('/api/*', authMiddleware(makeVerifier))` →
  `app.route('/api/reader', readerRoutes)` → `app.onError` (ApiError → その status/code、
  それ以外 → console.error して 500 internal、メッセージ非公開) →
  `app.notFound` (404 not_found)
- index.ts: `export default { fetch: createApp(env => new FirebaseTokenVerifier(env)).fetch }` 相当のみ

### package.json scripts

`dev` (wrangler dev)、`deploy` (wrangler deploy)、`test` (vitest run)、
`types` (wrangler types)、`db:apply:local` / `db:diff:remote` / `db:apply:remote`
(sqlite3def ベースのスキーマ適用、`scripts/db-apply.sh` 経由)

### テスト設計

- vitest.config.ts: `cloudflareTest()` プラグイン + `wrangler: { configPath: './wrangler.jsonc' }` +
  miniflare bindings で ALLOWED_UID=test-uid。Node の `fs` で `schema.sql` を読み、内容を
  `TEST_SCHEMA_SQL` binding として渡す。setup ファイル (test/setup.ts) で、まだ適用されていなければ
  (sqlite_master に reader_documents テーブルが無ければ) `TEST_SCHEMA_SQL` を `;` 区切りで
  statement ごとに `env.DB.prepare(stmt).run()` して適用する (migrations の仕組みは使わないため
  自前の冪等ガード)。isolatedStorage: true で各テストが独立 DB
- テストは `createApp(stubVerifier)` に直接 request する。stub は
  「固定 uid を返す」「常に throw する」の 2 種を用意し、Google の cert エンドポイントは一切モックしない
- test/auth.test.ts: ヘッダなし 401 / `Bearer ` でない形式 401 / verify throw で 401 /
  uid 不一致 403 / uid 一致 200 / health は認証なしで 200
- test/reader-documents.test.ts: 作成 201 と echo 内容 / 一覧が created_at 降順 /
  preview が 300 文字で切れて text を含まない / limit+1 と nextCursor (3 ページ跨ぎで全件・重複なし) /
  壊れた cursor 400 / filter=archived / archive → active 一覧から消える /
  archive 済みへの archive が 200 (冪等) / unarchive で戻る / 存在しない id 404 /
  text 空・欠落フィールドで 400
- test/reader-comments.test.ts: quote あり/なし作成 201 / 一覧が created_at 昇順 /
  includeArchived=false でアーカイブ済み除外、true で包含 / 存在しない document への作成 404 /
  comment の archive/unarchive / body 空 400

## MagonoteKit (共有 SPM パッケージ)

Core (全ツール共通) と Reader (ツール固有の型) にディレクトリを分ける。外部依存ゼロ
(Foundation + URLSession のみ。Firebase は各アプリ側に閉じる = DIP)。

### Core/

- AuthTokenProvider.swift: `public protocol AuthTokenProvider: Sendable { func idToken() async throws -> String }`。
  各アプリが Firebase の `getIDToken()` で実装 (token 保存はしない、Firebase が自動リフレッシュ)
- APIError.swift:
  `public enum APIError: Error { case unauthorized, forbidden, notFound, validation(String), server(status: Int, message: String), network(any Error), decoding(any Error) }`。
  サーバーのエラー envelope `{ error: { code, message } }` をデコードして code → case にマップ
- JSONCoding.swift: 共有 `JSONDecoder`/`JSONEncoder` (`dateDecodingStrategy = .millisecondsSince1970`、
  key 変換なし — API が既に camelCase)
- MagonoteAPIClient.swift:
  - `public struct MagonoteAPIClient: Sendable`
  - `public init(baseURL: URL, tokenProvider: any AuthTokenProvider, session: URLSession = .shared)`
  - 内部 `func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: (some Encodable)? ) async throws -> Data` —
    URL 構築 → `Authorization: Bearer <idToken()>` 注入 → 実行 →
    2xx なら Data、それ以外は envelope をデコードして APIError を throw。
    URLError は `.network`、デコード失敗は `.decoding` に包む
  - `func get<T: Decodable>(...)`, `func post<T: Decodable>(...)` の薄い typed ヘルパー

### Reader/

- Models.swift (全型 Codable + Sendable + Equatable、entity は Identifiable):
  - `public struct Document { id: String, text: String, sourceAppName: String, sourceMachineName: String, capturedAt: Date, createdAt: Date, archivedAt: Date? }`
  - `public struct DocumentSummary { id, preview: String, sourceAppName, sourceMachineName, capturedAt, createdAt, archivedAt }`
  - `public struct Comment { id: String, documentId: String, body: String, quote: String?, createdAt: Date, archivedAt: Date? }`
  - `public struct DocumentPage { documents: [DocumentSummary], nextCursor: String? }`
  - `public struct NewDocument { text, sourceAppName, sourceMachineName, capturedAt: Date }`
  - `public enum DocumentFilter: String, Sendable { case active, archived }`
  - Document / DocumentSummary / Comment に `public var isArchived: Bool { archivedAt != nil }`
- ReaderAPI.swift — `extension MagonoteAPIClient` (ツール追加時はこのパターンで extension を足す):
  - `createDocument(_ new: NewDocument) async throws -> Document`
  - `listDocuments(filter: DocumentFilter = .active, cursor: String? = nil, limit: Int = 30) async throws -> DocumentPage`
  - `document(id: String) async throws -> Document`
  - `archiveDocument(id: String) async throws -> Document` / `unarchiveDocument(id: String) async throws -> Document`
  - `comments(documentID: String, includeArchived: Bool = false) async throws -> [Comment]`
  - `createComment(documentID: String, body: String, quote: String?) async throws -> Comment`
  - `archiveComment(id: String) async throws -> Comment` / `unarchiveComment(id: String) async throws -> Comment`

### Tests/

URLProtocol スタブを ephemeral URLSessionConfiguration に登録して検証:
Bearer ヘッダが注入される / unix ms → Date デコード / camelCase キーの round-trip /
404 envelope → .notFound、400 → .validation(message) / 通信エラー → .network /
createDocument の request body が仕様どおりの JSON になる

## macOS アプリ「Magonote」

menu bar 常駐アプリ。Reader のキャプチャ機能を最初のツールとしてホストし、
今後のツールは Tools/<name>/ とメニュー項目の追加で増やす。

### ファイル構成と責務

- MagonoteApp.swift — `MenuBarExtra` + `Settings` シーンの pure SwiftUI App。
  `@NSApplicationDelegateAdaptor(AppDelegate.self)` は FirebaseApp.configure() のためだけ。
  `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }` で Google ログインのコールバック処理。
  SessionStore / CaptureController を生成して `.environment` 注入
- MenuBarIcon: アイコン状態は `enum MenuBarIconState { case idle, success, failure }` を
  CaptureController が持ち、success/failure 遷移後 1.5 秒で Task が idle に戻す。
  SF Symbol: idle = `hand.point.up.left` 系、success = `checkmark.circle`、failure = `exclamationmark.circle`
- メニュー内容 (`.menuBarExtraStyle(.menu)`):
  「今すぐキャプチャ」(ショートカット表示付き、CaptureController.capture() を直接呼ぶ) /
  Divider / 「設定…」(SettingsLink) / 「Magonote を終了」⌘Q
- Session/SessionStore.swift (@Observable, @MainActor):
  - state: `user: User?` (Firebase の auth state listener で同期)、`var isSignedIn`
  - `signIn() async throws` — `NSApp.activate(ignoringOtherApps: true)` →
    設定ウィンドウを presenting window にして `GIDSignIn.sharedInstance.signIn(withPresenting:)` →
    `GoogleAuthProvider.credential(withIDToken:accessToken:)` → `Auth.auth().signIn(with:)`
  - `signOut()` と、dev 用の「セッションをリセット」(keychain の stale item 対策)
  - `struct FirebaseAuthTokenProvider: AuthTokenProvider` — `Auth.auth().currentUser?.getIDToken()`、
    currentUser が nil なら `.unauthorized` 相当のエラーを throw
- Support/APIClientFactory.swift: UserDefaults の `serverBaseURL` (デフォルトは prod URL) から
  `MagonoteAPIClient` を組み立てる。設定画面の URL 変更が次のリクエストから効く
- Tools/Reader/CaptureController.swift (@Observable, @MainActor): 下記フローだけを持ち、
  選択文字列の取得は SelectionTextReading に、通信は MagonoteAPIClient に、認証は
  SessionStore に委譲 (SRP)
- Tools/Reader/SelectionTextReader.swift: Cmd+C の送信と general pasteboard の更新待機を担当。
  pasteboard の snapshot、消去、復元は行わない
- SettingsView.swift: TabView 構成 —
  - アカウント: ログイン状態 (メールアドレス表示)、サインイン/サインアウトボタン、UID の
    コピーボタン (ALLOWED_UID 設定用)
  - Reader: `KeyboardShortcuts.Recorder(for: .readerCapture)`
  - 権限: `AXIsProcessTrusted()` の状態ドット (Timer で 2 秒ごと再評価) +
    「システム設定を開く」ボタン (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`)、
    通知許可の状態と再リクエストボタン
  - 詳細: サーバー URL テキストフィールド (localhost 切替用)、ログイン時に起動トグル
    (`SMAppService.mainApp.register/unregister`)

### ホットキー

sindresorhus/KeyboardShortcuts。内部は Carbon RegisterEventHotKey なので権限不要で
他アプリ最前面でも動作し、SwiftUI の Recorder view が設定画面にそのまま置ける。
`KeyboardShortcuts.Name("readerCapture", default: .init(.c, modifiers: [.control, .option, .command]))`。
リスナー登録はアプリ起動時に 1 回、`KeyboardShortcuts.onKeyUp(for: .readerCapture)` で
CaptureController.capture() を呼ぶ。

### キャプチャフロー (CaptureController.capture())

1. `AXIsProcessTrusted()` を guard。false なら `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
   で OS のプロンプトを出し、failure フィードバック
2. `SessionStore.isSignedIn` を guard。false なら「サインインが必要」フィードバック
3. `NSWorkspace.shared.frontmostApplication` から選択元アプリ名を取得
4. `NSPasteboard.general.changeCount` を記録
5. 最前面のアプリへ Cmd+C を送信
6. 上限 1 秒間、50ms 間隔で pasteboard の更新を待つ。最初の空でない文字列を取得し、
   pasteboard に残す。更新なし or 空文字列 → 「テキストが選択されていない」フィードバック
7. `NewDocument(text:, sourceAppName:, sourceMachineName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName, capturedAt: .now)`
   を `client.createDocument()` で POST
8. フィードバック (成功/失敗の全パスで必ず 1 回):
   - 成功: 通知「Xcode から 1,234 文字をキャプチャ」+ アイコン success
   - 失敗: 通知にエラー内容 (未選択 / 未サインイン / 権限なし / 通信失敗) + アイコン failure
   - 通知は UserNotifications (初回キャプチャ時に requestAuthorization)。許可されなくても
     アイコン変化で最低限のフィードバックが成立する

エラーは `enum CaptureError: Error { case notTrusted, notSignedIn, nothingSelected, network(APIError) }`
に正規化し、フィードバック文言への変換を 1 箇所に集約する。

### 権限・配布まわり

- entitlements: App Sandbox なし (必須 — 他アプリの Accessibility 要素を参照するため)。
  keychain-access-groups (`$(AppIdentifierPrefix)app.soprog.magonote.shared`) を追加
  (FirebaseAuth の macOS keychain エラー対策)
- Info.plist: `LSUIElement: true` (Dock 非表示) + Google ログインの URL scheme のみ。
  権限文字列は不要 (Accessibility は System Settings で付与、usage description キーは存在しない)
- 初回起動オンボーディング: 未サインイン or 未トラストの間は、設定を促す内容をメニューに表示

## iOS アプリ「Magonote」

Reader をホーム画面として実装。将来ツールが増えたらルートにツール切替を足す想定だが、
今回はツール 1 つなので Reader の一覧を直接ルートにする (YAGNI)。

### ファイル構成と責務

- MagonoteApp.swift — FirebaseApp.configure() (AppDelegate adaptor) +
  `.onOpenURL { GIDSignIn.sharedInstance.handle($0) }` + SessionStore を environment 注入。
  `isSignedIn` で LoginView / NavigationStack(DocumentListView) を切替
- Session/SessionStore.swift (@Observable, @MainActor): macOS 側と同じ責務
  (auth state listener、signIn(presenting:) は root UIViewController を渡す、signOut、
  FirebaseAuthTokenProvider)。実装は各アプリに閉じ、共通化しない
  (Firebase 依存を MagonoteKit に持ち込まないため)
- Support/APIClientFactory.swift: baseURL は Info.plist の設定値 (デフォルト prod) から生成
- Tools/Reader/ の stores:
  - DocumentListStore (@Observable, @MainActor):
    `items: [DocumentSummary]`, `filter: DocumentFilter`, `nextCursor: String?`,
    `isLoading`, `error: APIError?`。
    `refresh() async` (cursor リセットして 1 ページ目) / `loadMore() async` (nextCursor がある時のみ) /
    `setFilter(_:) async` / `archive(id:) async` / `unarchive(id:) async` (楽観的更新 + 失敗時ロールバック)
  - DocumentDetailStore (@Observable, @MainActor):
    `document: Document?`, `comments: [Comment]`, `showArchivedComments: Bool`。
    `load(id:) async` (document と comments を並行 fetch) / `archive()` / `unarchive()` /
    `addComment(body:quote:) async` / `archiveComment(id:)` / `unarchiveComment(id:)`
- Tools/Reader/ の views: DocumentListView / DocumentDetailView / CommentsSection /
  CommentComposerSheet / QuoteSelectionSheet / MarkdownTheme (ファイル 1 View)

### 画面 (Tools/Reader/ 配下)

1. LoginView — Google ボタンのみ (Session/)
2. DocumentListView — 取得元 (sourceAppName + sourceMachineName) + 相対日時 + preview 3 行の List。
   .refreshable、末尾 onAppear で loadMore、toolbar Menu で Active/Archived 切替、
   swipe でアーカイブ/解除。楽観的 UI (失敗時は戻して alert)
3. DocumentDetailView — メタデータヘッダー + MarkdownUI 本文 + 下部コメントセクション。
   toolbar にアーカイブ
4. コメント composer sheet — body 入力 + 引用チップ + 「引用を選択…」ボタン。
   コメントは swipe/context-menu でアーカイブ、セクションヘッダーに「アーカイブ済みを表示」トグル
5. QuoteSelectionSheet — raw テキストを iOS 18 `TextEditor(text:selection:)` で表示し
   ネイティブ選択 → 下部バーに選択中スニペット → 「引用に使う」で substring を返す。
   raw テキスト選択なのでレンダリング済みテキストとの位置マッピングが不要。
   (plan B: TextSelection が不安定なら UITextView representable に差し替え、データモデル変更なし)

Markdown レンダリング: gonzalezreal/swift-markdown-ui (MarkdownUI)。
CommonMark + GFM (code block / table / blockquote) 対応で SwiftUI Theme でスタイリング可能。
注意: 標準 .gitHub テーマは背景がライト固定なので、code block 等の背景を
Color(.secondarySystemBackground) などの semantic color にしたカスタム Theme を定義して
ダーク/ライト両対応にする

## XcodeGen project.yml の要点

- 共通: SWIFT_VERSION 6.0、CODE_SIGN_STYLE Automatic (personal team)。
  プロジェクト名・ターゲット名はどちらも Magonote (ディレクトリが分かれているので衝突しない)
- iOS (bundle: app.soprog.magonote.ios): packages = firebase-ios-sdk (from 12.0.0),
  GoogleSignIn-iOS (from 8.0.0), swift-markdown-ui (from 2.4.0), MagonoteKit (path)。
  Info: CFBundleURLTypes に REVERSED_CLIENT_ID の URL scheme、UILaunchScreen: {}
- macOS (bundle: app.soprog.magonote.macos): 上記 + KeyboardShortcuts (from 2.0.0)、MarkdownUI なし。
  Info: LSUIElement true + URL scheme。entitlements: keychain-access-groups のみ (sandbox キーなし)
- GoogleService-Info.plist は sources に resources phase で参照 (未配置ならビルドが明確に失敗する)
- REVERSED_CLIENT_ID は project.yml にベタ書きで許容 (OAuth client 識別子は配布アプリの
  Info.plist に常に公開されるもので秘密ではない)

## ビルドフェーズ (順序 + 検証、Linear sub issue と 1:1 対応)

- DEV-2 スキャフォールド: .gitignore、README 骨子、ディレクトリツリー、MagonoteKit スタブ、
  本設計をコミット。検証: ダミーの plist / xcodeproj を置いて git status に出ないこと
- DEV-3 外部セットアップ (手動、README に記載):
  Firebase プロジェクト作成 → Google provider 有効化 → アプリ 2 つ登録
  (app.soprog.magonote.ios / app.soprog.magonote.macos) → plist 2 つダウンロード配置。
  Cloudflare: wrangler login → d1 create magonote → kv namespace create FIREBASE_CERT_CACHE →
  id を wrangler.jsonc に記入 → ALLOWED_UID は仮値で secret put (DEV-6 で実 UID に更新) + .dev.vars
- DEV-4 Backend: schema.sql → db.ts → tools/reader/ → auth.ts → app.ts/index.ts → tests。
  検証: npm test green / npm run db:apply:local + wrangler dev で /api/health curl /
  wrangler deploy して prod /api/health curl。実 token での検証は DEV-6 の初 POST で行う
- DEV-5 MagonoteKit: models → client → URLProtocol tests。検証: swift test
- DEV-6 macOS アプリ: (1) XcodeGen skeleton + MenuBarExtra 起動 →
  (2) hotkey と menu bar の両方から選択元アプリの文字列を取得できることを検証 →
  (3) Google sign-in、コンソールの UID を wrangler secret put ALLOWED_UID →
  (4) wrangler dev への POST を d1 execute --local の select で確認 → (5) prod へ向けて通知確認
- DEV-7 iOS アプリ: (1) skeleton + login → (2) 一覧 + pagination (DEV-6 の実データで) →
  (3) 詳細 + MarkdownUI をライト/ダーク両方で確認 → (4) アーカイブ → (5) コメント + 引用選択
  (quote の round-trip を d1 execute で確認)
- DEV-8 仕上げ: README をフレッシュクローン視点で完成、エラーパス確認
  (機内モード、server 500、未ログインでのキャプチャ)

## リスク・注意点

1. App Sandbox OFF は必須 (他アプリへ Cmd+C を送信するため)。
   App Store 配布は不可の設計 — 個人利用なので許容
2. Accessibility の信頼はバイナリ署名単位。personal team の安定した証明書で署名し、
   テストは一貫した場所 (Xcode 実行 or /Applications) から行う
3. Cmd+C の待機中に別のアプリが pasteboard へ文字列を書き込むと、その文字列を取得する
   可能性がある。個人用ツールの簡潔さを優先し、アプリ固有連携は追加しない
4. FirebaseAuth macOS の keychain エラー → keychain-access-groups entitlement で対策
5. MarkdownUI のダークモード → カスタム Theme 必須
6. iOS 18 TextSelection が不安定なら UITextView representable に差し替え (plan B)
7. KV binding 忘れは deploy 時でなく runtime で失敗 → DEV-4 の curl 検証で捕捉
8. vitest と @cloudflare/vitest-pool-workers はバージョン結合があるので peer range に従って入れる

## 作業の進め方 (Linear 運用)

親 issue は DEV-1「Magonote Reader 爆誕」(team: Dev)。PM が GitHub issue を運用するように
Linear へプランとログを記録し続け、親・sub どちらの issue を指定されても、まっさらな
セッションがユーザーの指図なしで再開できる状態を常に保つ。

### Status 運用

Todo → In Progress (AI) (作業開始時に即更新) → In Human Review (ユーザーの手動作業や
実機確認・PR レビュー待ち) → Done。

### ロギング規律 (セッション再開可能性の担保)

- 作業の区切りごとに sub issue へコメント: やったこと / 決定したこと / 発生した論点 /
  残っていること / 関連コミットハッシュ
- 意思決定と論点は発生時に即コメントに記録する。形式: 「決定: 」「論点: 」「残: 」
- セッション終了時 (または中断時) はコメント末尾に必ず「現在地」と「次の一手」を書く
- description は常に最新スコープのスナップショットに保つ

### git 運用 (diff サイズとスコープで使い分け)

- main 直コミット: 振る舞いを持たない変更 (スキャフォールド、ドキュメント、設定、自明な修正)
- branch + Draft PR: 振る舞いを持つコードや設計判断を含む変更。branch 名は Linear の
  gitBranchName、PR に close/ref magic word。マージはユーザーが行う
- 1 PR は 1 sub issue のスコープを超えない。迷ったら PR
