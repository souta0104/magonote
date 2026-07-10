import { encodeCursor } from './tools/reader/schemas';

export interface Document {
  id: string;
  text: string;
  sourceAppName: string;
  sourceMachineName: string;
  capturedAt: number;
  createdAt: number;
  archivedAt: number | null;
}

export interface DocumentSummary {
  id: string;
  preview: string;
  sourceAppName: string;
  sourceMachineName: string;
  capturedAt: number;
  createdAt: number;
  archivedAt: number | null;
}

export interface Comment {
  id: string;
  documentId: string;
  body: string;
  quote: string | null;
  createdAt: number;
  archivedAt: number | null;
}

interface DocumentRow {
  id: string;
  text: string;
  source_app_name: string;
  source_machine_name: string;
  captured_at: number;
  created_at: number;
  archived_at: number | null;
}

interface DocumentSummaryRow {
  id: string;
  preview: string;
  source_app_name: string;
  source_machine_name: string;
  captured_at: number;
  created_at: number;
  archived_at: number | null;
}

interface CommentRow {
  id: string;
  document_id: string;
  body: string;
  quote: string | null;
  created_at: number;
  archived_at: number | null;
}

function toDocument(row: DocumentRow): Document {
  return {
    id: row.id,
    text: row.text,
    sourceAppName: row.source_app_name,
    sourceMachineName: row.source_machine_name,
    capturedAt: row.captured_at,
    createdAt: row.created_at,
    archivedAt: row.archived_at,
  };
}

function toDocumentSummary(row: DocumentSummaryRow): DocumentSummary {
  return {
    id: row.id,
    preview: row.preview,
    sourceAppName: row.source_app_name,
    sourceMachineName: row.source_machine_name,
    capturedAt: row.captured_at,
    createdAt: row.created_at,
    archivedAt: row.archived_at,
  };
}

function toComment(row: CommentRow): Comment {
  return {
    id: row.id,
    documentId: row.document_id,
    body: row.body,
    quote: row.quote,
    createdAt: row.created_at,
    archivedAt: row.archived_at,
  };
}

export interface InsertDocumentInput {
  text: string;
  sourceAppName: string;
  sourceMachineName: string;
  capturedAt: number;
}

export async function insertDocument(
  db: D1Database,
  input: InsertDocumentInput,
): Promise<Document> {
  const id = crypto.randomUUID();
  const createdAt = Date.now();
  await db
    .prepare(
      `INSERT INTO reader_documents
        (id, text, source_app_name, source_machine_name, captured_at, created_at, archived_at)
       VALUES (?, ?, ?, ?, ?, ?, NULL)`,
    )
    .bind(id, input.text, input.sourceAppName, input.sourceMachineName, input.capturedAt, createdAt)
    .run();

  return {
    id,
    text: input.text,
    sourceAppName: input.sourceAppName,
    sourceMachineName: input.sourceMachineName,
    capturedAt: input.capturedAt,
    createdAt,
    archivedAt: null,
  };
}

export interface ListDocumentsOptions {
  filter: 'active' | 'archived';
  limit: number;
  cursor?: { createdAt: number; id: string };
}

export interface ListDocumentsResult {
  documents: DocumentSummary[];
  nextCursor: string | null;
}

export async function listDocuments(
  db: D1Database,
  opts: ListDocumentsOptions,
): Promise<ListDocumentsResult> {
  const archivedCondition = opts.filter === 'active' ? 'archived_at IS NULL' : 'archived_at IS NOT NULL';
  const conditions = [archivedCondition];
  const params: unknown[] = [];

  if (opts.cursor) {
    conditions.push('(created_at < ? OR (created_at = ? AND id < ?))');
    params.push(opts.cursor.createdAt, opts.cursor.createdAt, opts.cursor.id);
  }

  const fetchLimit = opts.limit + 1;
  params.push(fetchLimit);

  const { results } = await db
    .prepare(
      `SELECT id, substr(text, 1, 300) AS preview, source_app_name, source_machine_name,
              captured_at, created_at, archived_at
       FROM reader_documents
       WHERE ${conditions.join(' AND ')}
       ORDER BY created_at DESC, id DESC
       LIMIT ?`,
    )
    .bind(...params)
    .all<DocumentSummaryRow>();

  const rows = results ?? [];
  const hasMore = rows.length > opts.limit;
  const page = hasMore ? rows.slice(0, opts.limit) : rows;
  const documents = page.map(toDocumentSummary);

  const last = documents[documents.length - 1];
  const nextCursor = hasMore && last ? encodeCursor({ createdAt: last.createdAt, id: last.id }) : null;

  return { documents, nextCursor };
}

export async function getDocument(db: D1Database, id: string): Promise<Document | null> {
  const row = await db
    .prepare(
      `SELECT id, text, source_app_name, source_machine_name, captured_at, created_at, archived_at
       FROM reader_documents WHERE id = ?`,
    )
    .bind(id)
    .first<DocumentRow>();

  return row ? toDocument(row) : null;
}

export async function setDocumentArchived(
  db: D1Database,
  id: string,
  archivedAt: number | null,
): Promise<Document | null> {
  const row = await db
    .prepare(
      `UPDATE reader_documents SET archived_at = ?
       WHERE id = ?
       RETURNING id, text, source_app_name, source_machine_name, captured_at, created_at, archived_at`,
    )
    .bind(archivedAt, id)
    .first<DocumentRow>();

  return row ? toDocument(row) : null;
}

export interface InsertCommentInput {
  body: string;
  quote?: string;
}

export async function insertComment(
  db: D1Database,
  documentId: string,
  input: InsertCommentInput,
): Promise<Comment | null> {
  const document = await getDocument(db, documentId);
  if (!document) {
    return null;
  }

  const id = crypto.randomUUID();
  const createdAt = Date.now();
  const quote = input.quote ?? null;

  await db
    .prepare(
      `INSERT INTO reader_comments (id, document_id, body, quote, created_at, archived_at)
       VALUES (?, ?, ?, ?, ?, NULL)`,
    )
    .bind(id, documentId, input.body, quote, createdAt)
    .run();

  return {
    id,
    documentId,
    body: input.body,
    quote,
    createdAt,
    archivedAt: null,
  };
}

export async function listComments(
  db: D1Database,
  documentId: string,
  includeArchived: boolean,
): Promise<Comment[] | null> {
  const document = await getDocument(db, documentId);
  if (!document) {
    return null;
  }

  const where = includeArchived
    ? 'document_id = ?'
    : 'document_id = ? AND archived_at IS NULL';

  const { results } = await db
    .prepare(
      `SELECT id, document_id, body, quote, created_at, archived_at
       FROM reader_comments
       WHERE ${where}
       ORDER BY created_at ASC, id ASC`,
    )
    .bind(documentId)
    .all<CommentRow>();

  return (results ?? []).map(toComment);
}

export async function setCommentArchived(
  db: D1Database,
  id: string,
  archivedAt: number | null,
): Promise<Comment | null> {
  const row = await db
    .prepare(
      `UPDATE reader_comments SET archived_at = ?
       WHERE id = ?
       RETURNING id, document_id, body, quote, created_at, archived_at`,
    )
    .bind(archivedAt, id)
    .first<CommentRow>();

  return row ? toComment(row) : null;
}
