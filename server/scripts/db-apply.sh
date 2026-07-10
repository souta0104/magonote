#!/usr/bin/env bash
# server/scripts/db-apply.sh
# schema.sql を正 (source of truth) として D1 のスキーマを宣言的に同期する。
# sqlite3def のオフライン diff モード (current.sql vs desired.sql) を使う理由:
# ローカル D1 の実体ファイルに sqlite3def を直接向けると、Cloudflare 内部テーブル
# _cf_METADATA の unquoted `key` カラム (sqlite3def v3.11.13 の DDL パーサーの制約で
# 予約語と衝突して構文エラーになる) を skip_tables で除外しても、パーサーがその
# テーブルの DDL 自体を読もうとして落ちるため機能しない。
# 代わりに `wrangler d1 export --no-data` で得たスキーマを一度パースして current.sql
# として渡す (_cf_METADATA は export に含まれないので回避できる)。
#
# Usage: db-apply.sh --local|--remote [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."

command -v sqlite3def >/dev/null 2>&1 || {
  echo "sqlite3def not found. Install: brew install sqldef/sqldef/sqlite3def" >&2
  exit 1
}

TARGET=${1:-}
case "$TARGET" in
  --local|--remote) ;;
  *)
    echo "usage: $0 --local|--remote [--dry-run]" >&2
    exit 1
    ;;
esac
DRY_RUN=${2:-}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ "$TARGET" = "--local" ]; then
  # ローカル D1 の sqlite ファイルを実体化 (初回 clone 直後などまだ無い場合に備える)
  npx wrangler d1 execute magonote --local --command "SELECT 1" > /dev/null
fi

# 1. 現行スキーマを export (データなし)
npx wrangler d1 export magonote "$TARGET" --no-data --output "$TMP/current-raw.sql"

# wrangler の export には sqlite3def の DDL パーサーが読めない行が混じるので取り除く:
# - PRAGMA 文 (sqlite3def の DDL パーサーが非対応)
# - `DELETE FROM sqlite_sequence` (旧 d1_migrations テーブルの AUTOINCREMENT に由来する
#   残骸で、テーブル定義ではない)
# また reader_documents.text は SQL 型キーワードと同名で sqlite3def v3.11.13 の
# パーサーと衝突するため、両ファイルとも quote した "text" に統一する
# (schema.sql 側もこの理由で "text" と quote 済み)。
# grep -v は残る行が 0 件だと exit 1 を返す (未デプロイでテーブルが 1 つもない DB の場合に
# 起こりうる = current.sql が空になるのは正当なケースなので `|| true` で握りつぶす)
{ grep -vE '^(PRAGMA |DELETE FROM sqlite_sequence)' "$TMP/current-raw.sql" || true; } \
  | sed -E 's/^([[:space:]]*)text([[:space:]]+TEXT )/\1"text"\2/' \
  > "$TMP/current.sql"

# 2. sqlite3def のオフラインモードで差分 DDL を生成 (current.sql vs schema.sql)
# d1_migrations: 旧 migrations 方式の残骸テーブル / sqlite_sequence: SQLite 内部管理テーブル
sqlite3def "$TMP/current.sql" --enable-drop \
  --config-inline='skip_tables: "d1_migrations|sqlite_sequence"' \
  --file schema.sql > "$TMP/diff.sql"

echo "--- diff DDL ($TARGET) ---"
cat "$TMP/diff.sql"

if [ "$DRY_RUN" = "--dry-run" ]; then
  exit 0
fi

# sqlite3def は差分なしのとき "-- Nothing is modified --" のみを出力する。
# コメント行 (-- ...) を除いて実 DDL が残っていなければ適用不要と判断する。
if ! grep -v '^--' "$TMP/diff.sql" | grep -qE '[A-Za-z]'; then
  echo "no changes to apply"
  exit 0
fi

# D1 は Durable Object 上に実装されており、SQL の BEGIN/COMMIT (トランザクション) 文を
# 直接実行できない (state.storage.transaction() 相当の内部 API を使う必要があるため)。
# sqlite3def の diff 出力はトランザクションで DDL を包むので、コメント行と合わせて
# 取り除いてから wrangler d1 execute に渡す。
grep -vE '^(--|BEGIN;|COMMIT;)' "$TMP/diff.sql" > "$TMP/diff-apply.sql"

# 3. 差分 DDL を適用
npx wrangler d1 execute magonote "$TARGET" --yes --file "$TMP/diff-apply.sql"
