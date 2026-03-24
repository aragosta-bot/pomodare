# 🍅 Pomodare

A macOS menubar app where two remote people compete to stay focused through shared Pomodoro rounds.

## How It Works

- **Host** creates a session → gets a 4-letter code (e.g. `BRAT`)
- **Guest** enters the code → both land in the Lobby
- A 25-minute focus round starts — both must click **🍅 I'm working** to commit
- At the end of each round, whoever committed wins a point
- 5 rounds → final scoreboard
- Real-time sync via Supabase REST polling (every 3s)

---

## Setup

### 1. Create a Supabase Project

1. Go to [supabase.com](https://supabase.com) and create a free project
2. In the SQL editor (**Database → SQL Editor**), paste and run the contents of `schema.sql`
3. Copy your credentials from **Project Settings → API**:
   - **Project URL** — looks like `https://abcdefgh.supabase.co`
   - **anon / public key** — the `anon` JWT

### 2. Add Credentials to Info.plist

Open `Pomodare/Info.plist` and replace the placeholder values:

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_PROJECT_ID.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>YOUR_ANON_KEY_HERE</string>
```

### 3. Build and Run

```bash
# Regenerate Xcode project first (if needed):
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
cd ~/Developer/pomodare
ruby generate_project.rb

# Then open in Xcode:
open Pomodare.xcodeproj
# Press Cmd+R
```

Or from the command line:
```bash
xcodebuild -project Pomodare.xcodeproj \
           -scheme Pomodare \
           -configuration Debug \
           build
```

---

## Project Structure

```
Pomodare/
├── PomodareApp.swift          @main — MenuBarExtra scene + MenuBarLabel icon
├── AppDelegate.swift          Hides app from Dock (LSUIElement = true)
├── Extensions.swift           Misc helpers
├── Info.plist                 Bundle config + Supabase credentials (SUPABASE_URL, SUPABASE_ANON_KEY)
├── Models/
│   ├── AppState.swift         @Observable state — SessionPhase enum + timer + partner status
│   ├── SupabaseService.swift  REST client — createSession, joinSession, updateParticipant, 3s poll
│   └── ActivityTracker.swift  (legacy) CGEventTap idle detection
└── Views/
    └── MenuBarView.swift      MenuBarView + Home/Waiting/Session/Finished sub-views
schema.sql                     Supabase schema — run this in your project's SQL editor
```

---

## Architecture

### SessionPhase State Machine

```
idle → waiting → lobby → active → roundResult → (next round or) finished
                                ↓
                             breakTime
```

| Phase | Description |
|-------|-------------|
| `idle` | No session — home screen |
| `waiting` | Host created session, waiting for guest |
| `lobby` | Both connected, about to start |
| `active` | 25-min focus round counting down |
| `breakTime` | Short break between rounds |
| `roundResult` | Round ended — commit/give-up shown |
| `finished` | All rounds done — scoreboard |

### Networking

- **Pure URLSession** — no third-party SDKs
- **Polling every 3s** — `SupabaseService.subscribeToSession` as Realtime fallback
- **Supabase REST API** with open RLS policies (fine for private beta)
- No auth — each user gets a random UUID on first launch (stored in memory for POC)

### State

- `AppState` is `@Observable` (macOS 14+ / iOS 17+)
- Passed via `@Environment` through the view tree
- `SupabaseService` is a singleton accessed directly; could be injected for tests

---

## Known Limitations / TODOs

- **UUID persistence**: User UUID resets on every launch. Use `UserDefaults` or Keychain for real persistence.
- **No Realtime WebSocket**: Uses 3s polling. Upgrade to Supabase Realtime for sub-second sync.
- **Host drives round transitions**: Only host should call `updateSessionState`. Currently both could — add role checks.
- **No break timer**: `breakTime` phase transitions are not wired up yet.
- **Session cleanup**: Old sessions linger. Add a cleanup job or TTL.
- **No Accessibility permission needed**: The POC dropped `CGEventTap` (ActivityTracker). Add it back for idle detection.

---

## License

MIT
