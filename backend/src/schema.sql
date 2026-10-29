CREATE TABLE IF NOT EXISTS users (
 id uuid PRIMARY KEY, email text UNIQUE NOT NULL, username text UNIQUE NOT NULL,
 name text NOT NULL, password text, role text NOT NULL DEFAULT 'parent'
 CHECK(role IN ('admin','staff','parent','child')), verified boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS challenges (
 id uuid PRIMARY KEY, user_id uuid REFERENCES users(id) ON DELETE CASCADE,
 kind text NOT NULL, digest text NOT NULL, attempts int NOT NULL DEFAULT 0,
 expires_at timestamptz NOT NULL, payload jsonb NOT NULL DEFAULT '{}'
);
CREATE TABLE IF NOT EXISTS children (
 id uuid PRIMARY KEY, parent_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 name text NOT NULL, age int NOT NULL CHECK(age BETWEEN 1 AND 17),
 daily_limit int NOT NULL DEFAULT 120 CHECK(daily_limit BETWEEN 15 AND 1440),
 nfc_hash text, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS child_nfc_unique ON children(nfc_hash) WHERE nfc_hash IS NOT NULL;
CREATE TABLE IF NOT EXISTS devices (
 id uuid PRIMARY KEY, child_id uuid NOT NULL REFERENCES children(id) ON DELETE CASCADE,
 name text NOT NULL, platform text NOT NULL DEFAULT 'Android',
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS agreements (
 id uuid PRIMARY KEY, child_id uuid NOT NULL REFERENCES children(id) ON DELETE CASCADE,
 title text NOT NULL, reward int NOT NULL CHECK(reward BETWEEN 1 AND 120),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS checkins (
 id uuid PRIMARY KEY, child_id uuid NOT NULL REFERENCES children(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS child_links (
 user_id uuid UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 child_id uuid UNIQUE NOT NULL REFERENCES children(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS shared_locations (
 child_id uuid PRIMARY KEY REFERENCES children(id) ON DELETE CASCADE,
 latitude double precision NOT NULL, longitude double precision NOT NULL,
 accuracy double precision NOT NULL, updated_at timestamptz NOT NULL DEFAULT now()
);
