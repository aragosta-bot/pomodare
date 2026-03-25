# Pomodare 🍅

Synchronized Pomodoro timer for two remote people. Connect via a 4-letter code, declare you're working, and track rounds together.

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
