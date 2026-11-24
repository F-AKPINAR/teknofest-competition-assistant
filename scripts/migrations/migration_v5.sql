-- v5: kimlik doğrulama (id + şifre) için users tablosunu genişletme,
-- İçerik Yöneticisi rolü ekleme, belge yönetimi (documents/document_chunks) tabloları.

-- tickets tablosu users(id)'e FK ile bağlı olduğu için, users tablosunu
-- (CHECK constraint'i genişletmek üzere) DROP+RENAME ile yeniden oluştururken
-- SQLite bunu foreign key ihlali sayıp hata verir. defer_foreign_keys, FK
-- kontrolünü transaction'ın sonuna erteler (id'ler aynı kalacağı için sorun
-- kalmayacak).
PRAGMA defer_foreign_keys = TRUE;

-- Önce, users(id)'e referans veren ama artık karşılığı olmayan (orphan)
-- satırları temizle - yoksa transaction sonunda FK kontrolü yine patlar.
UPDATE tickets SET user_id = NULL WHERE user_id IS NOT NULL AND user_id NOT IN (SELECT id FROM users);
UPDATE tickets SET assigned_to = NULL WHERE assigned_to IS NOT NULL AND assigned_to NOT IN (SELECT id FROM users);
UPDATE ticket_events SET actor_id = NULL WHERE actor_id IS NOT NULL AND actor_id NOT IN (SELECT id FROM users);

-- SQLite'ta CHECK constraint'i doğrudan ALTER edilemediği için users tablosunu
-- yeniden oluşturup mevcut satırları taşıyoruz.
CREATE TABLE users_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('yarisci', 'hakem', 'koordinator', 'admin', 'icerik_yoneticisi')),
  team_name TEXT,
  password_hash TEXT,
  password_salt TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO users_new (id, name, email, role, team_name, created_at)
  SELECT id, name, email, role, team_name, created_at FROM users;

DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

-- Demo password hashes are intentionally NOT committed. Run /api/setup (see README)
-- to set them from the DEMO_PASSWORD secret.
UPDATE users SET password_hash = NULL, password_salt = 'salt-hakem'
  WHERE email = 'hakem@demo.t3';
UPDATE users SET password_hash = NULL, password_salt = 'salt-koordinator'
  WHERE email = 'koordinator@demo.t3';
UPDATE users SET password_hash = NULL, password_salt = 'salt-admin'
  WHERE email = 'admin@demo.t3';

INSERT INTO users (name, email, role, password_hash, password_salt) VALUES
  ('Demo İçerik Yöneticisi', 'icerik@demo.t3', 'icerik_yoneticisi',
   NULL, 'salt-icerik');

-- Belge yönetimi: yüklenen şartname/kılavuz/SSS kaynakları + geçerlilik durumu (AKIŞ 02)
CREATE TABLE IF NOT EXISTS documents (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  competition_id TEXT NOT NULL,
  title TEXT NOT NULL,
  filename TEXT NOT NULL,
  version TEXT,
  status TEXT NOT NULL DEFAULT 'isleniyor' CHECK (status IN ('isleniyor', 'aktif', 'pasif', 'hata')),
  chunk_count INTEGER NOT NULL DEFAULT 0,
  total_chunks INTEGER NOT NULL DEFAULT 0,
  uploaded_by INTEGER REFERENCES users(id),
  uploaded_at TEXT NOT NULL DEFAULT (datetime('now')),
  r2_key TEXT
);

-- Belgeden çıkarılan, henüz embed edilmemiş/edilmiş parçalar (batch işleme için)
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
