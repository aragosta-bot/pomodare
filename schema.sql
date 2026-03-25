-- Pomodare — Supabase Schema (v2)
-- Drop old tables if they exist
DROP TABLE IF EXISTS participants CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;

-- Sessions table matching the Go code
CREATE TABLE sessions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code            TEXT NOT NULL UNIQUE,
  state           TEXT NOT NULL DEFAULT 'waiting',  -- waiting|lobby|active|break|finished
  host_id         TEXT NOT NULL,
  guest_id        TEXT,
  round           INT NOT NULL DEFAULT 1,
  timer_started_at TIMESTAMPTZ,
  host_declared   BOOLEAN NOT NULL DEFAULT FALSE,
  guest_declared  BOOLEAN NOT NULL DEFAULT FALSE,
  host_gave_up    BOOLEAN NOT NULL DEFAULT FALSE,
  guest_gave_up   BOOLEAN NOT NULL DEFAULT FALSE,
  host_score      INT NOT NULL DEFAULT 0,
  guest_score     INT NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- Row Level Security (open for POC — no auth required)
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "open_sessions" ON sessions FOR ALL USING (true) WITH CHECK (true);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sessions_updated_at
  BEFORE UPDATE ON sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
