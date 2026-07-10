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
