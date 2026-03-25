# Pomodare 🍅

> Your terminal. Your rival. Your focus.

Synchronized Pomodoro timer for two remote people. Connect via a 4-letter code, declare you're working, and outwork your friend.

## What it does

25 minutes. One code. Two people.  
Press `P` to declare you're working — your rival sees it instantly.  
Survive 20 minutes and the round counts toward your score.  
Give up early and they'll know. After 5 rounds, the score speaks for itself.

## Install

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

No Go installation required.

## Build from source

```bash
git clone https://github.com/aragosta-bot/pomodare
cd pomodare
go build -o pomodare .
./pomodare
```

Requires Go 1.22+.

## How to play

| Screen | Key | Action |
|--------|-----|--------|
| Home | `N` | New session (you're the host) |
| Home | `J` | Join a session with a code |
| Active | `P` | Declare you're working |
| Active | `G` | Give up (before the 20-min mark) |
| Any | `Q` | Quit |

## The rules

- **25 min work / 5 min break.** Classic Pomodoro. No negotiation.
- **Press `P`** in the first 5 minutes to declare you're in. Your rival sees it.
- **Round counts** only if you last 20 minutes. Quit early and it doesn't.
- **Give up with `G`** before 20 minutes — honest, but it won't count.
- After 5 rounds: `You: 4/5 | Rival: 3/5`. That's the game.

## Backend

Supabase free tier. Sessions are deleted when the host quits. Schema in `schema.sql`.

Override the defaults with environment variables:
```bash
export POMODARE_SUPABASE_URL=https://...
export POMODARE_SUPABASE_ANON_KEY=eyJ...
```

## License

MIT
