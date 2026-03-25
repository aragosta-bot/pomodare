# Pomodare 🍅

Synchronized Pomodoro timer for two remote people.

## Install

Download the latest binary for your platform from [Releases](https://github.com/aragosta-bot/pomodare/releases):

**macOS (Apple Silicon):**
```bash
curl -L https://github.com/aragosta-bot/pomodare/releases/latest/download/pomodare-darwin-arm64 -o pomodare
chmod +x pomodare
./pomodare
```

**macOS (Intel):**
```bash
curl -L https://github.com/aragosta-bot/pomodare/releases/latest/download/pomodare-darwin-amd64 -o pomodare
chmod +x pomodare
./pomodare
```

**Linux:**
```bash
curl -L https://github.com/aragosta-bot/pomodare/releases/latest/download/pomodare-linux-amd64 -o pomodare
chmod +x pomodare
./pomodare
```

No Go installation required. Connect via a 4-letter code, declare you're working, and track rounds together.

## What it does

- 25min work / 5min break timer, synchronized via Supabase
- Both people connect via a shared 4-letter session code
- Press `P` in the first 5 minutes to declare "I'm working"
- Press `G` to give up (only before the 20-minute mark)
- Round counts toward your score if you declared and didn't give up
- After 5 rounds: "Ty: 4/5 | Partner: 3/5"

## Requirements

- Go 1.22+
- A terminal

## Setup

```bash
cd ~/Developer/pomodare

# Install dependencies
go mod tidy

# Build
go build -o pomodare .

# Run
./pomodare
```

## Environment variables (optional)

```bash
export POMODARE_SUPABASE_URL=https://...
export POMODARE_SUPABASE_ANON_KEY=eyJ...
```

Falls back to hardcoded defaults if not set.

## Controls

| Screen   | Key | Action              |
|----------|-----|---------------------|
| Home     | `N` | New session (host)  |
| Home     | `J` | Join session        |
| Lobby    | `S` | Start round (host)  |
| Active   | `P` | Declare working     |
| Active   | `G` | Give up             |
| Any      | `Q` | Quit                |

## File structure

```
main.go       — entry point
model.go      — Bubble Tea model (screens, state machine)
supabase.go   — REST client + session sync
timer.go      — timer logic and phase management
styles.go     — Lip Gloss styles
schema.sql    — Supabase table schema
```

## Database

The Supabase `sessions` table is defined in `schema.sql`. Run it in the Supabase SQL editor to set up the backend.

### Session cleanup

When the host quits (any screen), the session is automatically deleted from Supabase via the Go client.

Supabase's `pg_cron` extension is not enabled on this project, so there is no scheduled cleanup job. To manually remove stale sessions (older than 2 hours), run the following SQL in the Supabase SQL editor:

```sql
DELETE FROM sessions WHERE created_at < now() - interval '2 hours';
```

To enable automatic cleanup, activate the `pg_cron` extension in your Supabase project and run:

```sql
SELECT cron.schedule('cleanup-old-sessions', '0 * * * *',
  $$DELETE FROM sessions WHERE created_at < now() - interval '2 hours'$$);
```
