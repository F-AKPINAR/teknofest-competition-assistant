-- v11: yarışma bazlı iki hakem hesabı + yarışmacı girişi
-- Password hashes are intentionally NOT committed; /api/setup sets them from the DEMO_PASSWORD secret.

INSERT INTO users (name, email, role, password_salt, password_hash, competitions)
VALUES ('İHA Hakemi', 'iha.hakem@demo.t3', 'hakem', 'salt-iha',
        NULL, 'iha')
ON CONFLICT(email) DO UPDATE SET
  name = excluded.name, role = excluded.role,
  password_salt = excluded.password_salt, password_hash = excluded.password_hash,
  competitions = excluded.competitions;

INSERT INTO users (name, email, role, password_salt, password_hash, competitions)
VALUES ('Blokzincir Hakemi', 'blok.hakem@demo.t3', 'hakem', 'salt-blok',
        NULL, 'blokzincir')
ON CONFLICT(email) DO UPDATE SET
  name = excluded.name, role = excluded.role,
  password_salt = excluded.password_salt, password_hash = excluded.password_hash,
  competitions = excluded.competitions;

-- Yarışmacı hesabı zaten vardı ama şifresi yoktu; giriş yapabilsin diye ekliyoruz.
INSERT INTO users (name, email, role, password_salt, password_hash, competitions)
VALUES ('Demo Yarışmacı', 'yarisci@demo.t3', 'yarisci', 'salt-yarisci',
        NULL, NULL)
ON CONFLICT(email) DO UPDATE SET
  role = excluded.role,
  password_salt = excluded.password_salt, password_hash = excluded.password_hash;
