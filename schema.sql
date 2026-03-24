-- Pomodare — Supabase Schema
-- Run this in your Supabase project's SQL editor.

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,                         -- 4-letter human-readable code (e.g. "BRAT")
  host_uuid UUID NOT NULL,
  guest_uuid UUID,
  state TEXT NOT NULL DEFAULT 'waiting',       -- waiting|lobby|active|break|round_result|finished
  round_number INT NOT NULL DEFAULT 0,
  timer_started_at TIMESTAMPTZ,
  phase_duration_sec INT NOT NULL DEFAULT 1500, -- 25 min default
  total_rounds INT NOT NULL DEFAULT 5,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE,
  user_uuid UUID NOT NULL,
  role TEXT NOT NULL,                          -- 'host' | 'guest'
  committed BOOLEAN DEFAULT FALSE,
  gave_up BOOLEAN DEFAULT FALSE,
  rounds_won INT NOT NULL DEFAULT 0,
  last_seen_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(session_id, user_uuid)
);

-- Row Level Security (open for POC — no auth required)
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "open_sessions"     ON sessions     FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "open_participants" ON participants FOR ALL USING (true) WITH CHECK (true);

-- Optional: auto-update updated_at
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
