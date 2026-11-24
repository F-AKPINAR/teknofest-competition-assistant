-- Current production schema (snapshot of the live D1 database, November 2026).
-- Equivalent to schema.sql + migration_v2 ... migration_v13 applied in order.
-- Use this file for a fresh setup:  npm run db:current:remote
-- Demo staff accounts are NOT seeded here; run /api/setup?key=<SETUP_KEY> after deploying.

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('yarisci','hakem','koordinator','admin','icerik_yoneticisi')),
  team_name TEXT,
  password_hash TEXT,
  password_salt TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  competitions TEXT            -- reviewer scope, comma-separated competition ids; NULL = all
);

-- type: 'soru' (question escalated by the assistant) | 'itiraz' (appeal)
-- status: 'ai_cevapladi' | 'insana_yonlendirildi' | 'atandi' | 'cevaplandi' | 'kapatildi'
CREATE TABLE IF NOT EXISTS tickets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER REFERENCES users(id),
  type TEXT NOT NULL CHECK (type IN ('soru', 'itiraz')),
  category TEXT,
  question TEXT NOT NULL,
  ai_answer TEXT,
  ai_confidence REAL,
  ai_sources TEXT,             -- JSON: [{source_title, page, madde_no}]
  decision_reason TEXT,        -- appeals: the elimination/decision reason, if any
  status TEXT NOT NULL DEFAULT 'ai_cevapladi',
  assigned_to INTEGER REFERENCES users(id),
  human_answer TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  team_id TEXT,
  application_id TEXT,
  helpful INTEGER              -- NULL = no feedback, 1 = helpful, 0 = not helpful
);

CREATE TABLE IF NOT EXISTS ticket_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER NOT NULL REFERENCES tickets(id),
  actor_id INTEGER REFERENCES users(id),
  event_type TEXT NOT NULL,    -- 'olusturuldu' | 'atandi' | 'cevaplandi' | 'kapatildi'
  note TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Curated, human-approved FAQ pool (checked before RAG)
CREATE TABLE IF NOT EXISTS faqs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  competition_id TEXT NOT NULL,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  source_ticket_id INTEGER,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  sources TEXT                 -- JSON, copied from the ticket's AI sources
);

-- Specification documents uploaded by the Content Manager
CREATE TABLE IF NOT EXISTS documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  competition_id TEXT NOT NULL,
  title TEXT NOT NULL,
  filename TEXT NOT NULL,
  version TEXT,
  status TEXT NOT NULL DEFAULT 'isleniyor' CHECK (status IN ('isleniyor','aktif','pasif','hata')),
  chunk_count INTEGER NOT NULL DEFAULT 0,
  total_chunks INTEGER NOT NULL DEFAULT 0,
  uploaded_by INTEGER REFERENCES users(id),
  uploaded_at TEXT NOT NULL DEFAULT (datetime('now')),
  r2_key TEXT
);

CREATE TABLE IF NOT EXISTS document_chunks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  document_id INTEGER NOT NULL REFERENCES documents(id),
  vector_id TEXT NOT NULL,
  page INTEGER,
  madde_no TEXT,
  madde_title TEXT,
  text TEXT NOT NULL,
  embedded INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Raw PDFs in R2 that source badges link to
CREATE TABLE IF NOT EXISTS source_files (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  competition_id TEXT NOT NULL,
  source_title TEXT NOT NULL,
  filename TEXT,
  r2_key TEXT NOT NULL,
  uploaded_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_source_files_title ON source_files(source_title);

-- Every question asked, with its outcome (for the analytics dashboard)
CREATE TABLE IF NOT EXISTS question_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  competition_id TEXT,
  question TEXT NOT NULL,
  outcome TEXT,
  confidence REAL,
  created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_qlog_comp ON question_log(competition_id, created_at);
