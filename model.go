package main

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Screen states
type Screen int

const (
	ScreenHome    Screen = iota
	ScreenWaiting        // host waiting for partner
	ScreenJoin           // guest entering code
	ScreenLobby          // both connected, waiting for round start
	ScreenActive         // timer running
	ScreenBreak          // break between rounds
	ScreenResult         // final results
	ScreenSolo           // solo mode: local 25/5 timer
	ScreenSoloDone       // solo session ended
)

// Messages
type tickMsg time.Time
type sessionPollMsg struct {
	session *Session
	err     error
}
type sessionCreatedMsg struct {
	session *Session
	err     error
}
type sessionJoinedMsg struct {
	session *Session
	err     error
}
type roundStartedMsg struct {
	session *Session
	err     error
}
type actionDoneMsg struct {
	session *Session
	err     error
}

// buttonRegion tracks the screen position of a rendered button for mouse click detection.
type buttonRegion struct {
	label  string // action label, e.g. "new_session", "quit", "back"
	y1, y2 int    // row range (inclusive)
	x1, x2 int    // col range (inclusive)
}

// Model is the main application state
type Model struct {
	screen       Screen
	supabase     *SupabaseClient
	playerID     string
	isHost       bool
	session      *Session
	timer        TimerState
	codeInput    string
	errMsg       string
	pollTicker   int
	spinnerIdx   int // tomato animation frame index
	animTick     int // sub-tick counter so we can animate at ~150ms with a 150ms ticker
	explodeTimer int // counts down ticks while showing explode art
	width        int
	height       int

	// Solo mode state
	soloPhase   Phase         // PhaseWork or PhaseBreak
	soloStart   time.Time     // when current phase started (or resumed)
	soloPaused  bool
	soloElapsed time.Duration // accumulated elapsed before last pause
	soloRound   int           // current round (1-indexed)

	// Mouse click regions — rebuilt on every View() call
	buttons []buttonRegion
}

func NewModel() Model {
	return Model{
		screen:   ScreenHome,
		supabase: NewSupabaseClient(),
		playerID: generatePlayerID(),
	}
}

func generatePlayerID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return hex.EncodeToString(b)
}

// cleanupSession deletes the session from Supabase if this player is the host.
func (m Model) cleanupSession() {
	if m.session != nil && m.isHost {
		_ = m.supabase.DeleteSession(m.session.ID)
	}
}

func (m Model) Init() tea.Cmd {
	return tickCmd()
}

func tickCmd() tea.Cmd {
	return tea.Tick(150*time.Millisecond, func(t time.Time) tea.Msg {
		return tickMsg(t)
	})
}

func pollSessionCmd(s *SupabaseClient, sessionID string) tea.Cmd {
	return func() tea.Msg {
		sess, err := s.GetSession(sessionID)
		return sessionPollMsg{session: sess, err: err}
	}
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tickMsg:
		// Advance tomato animation frame on every tick (~150ms per frame)
		m.spinnerIdx = (m.spinnerIdx + 1) % len(TomatoFrames)

		// Tick down the round-end explode animation
		if m.explodeTimer > 0 {
			m.explodeTimer--
		}

		cmds := []tea.Cmd{tickCmd()}

		// Poll for session updates every ~3 seconds (20 ticks at 150ms)
		if m.session != nil {
			m.pollTicker++
			if m.pollTicker >= 20 {
				m.pollTicker = 0
				cmds = append(cmds, pollSessionCmd(m.supabase, m.session.ID))
			}
		}

		// Check timer expiry
		if m.screen == ScreenActive && !m.timer.StartedAt.IsZero() {
			if m.timer.IsExpired() {
				return m.handleTimerExpired()
			}
		}
		if m.screen == ScreenBreak && !m.timer.StartedAt.IsZero() {
			if m.timer.IsExpired() {
				return m.handleBreakExpired()
			}
		}

		// Solo timer expiry
		if m.screen == ScreenSolo && !m.soloPaused {
			elapsed := m.soloElapsed + time.Since(m.soloStart)
			phaseDur := WorkDuration
			if m.soloPhase == PhaseBreak {
				phaseDur = BreakDuration
			}
			if elapsed >= phaseDur {
				if m.soloPhase == PhaseWork {
					// Work done → break
					m.soloRound++ // increment when work phase completes
					m.soloPhase = PhaseBreak
					m.soloStart = time.Now()
					m.soloElapsed = 0
				} else {
					// Break done → next work (round already incremented when work ended)
					m.soloPhase = PhaseWork
					m.soloStart = time.Now()
					m.soloElapsed = 0
				}
			}
		}

		return m, tea.Batch(cmds...)

	case sessionPollMsg:
		if msg.err != nil {
			m.errMsg = msg.err.Error()
			return m, nil
		}
		return m.handleSessionUpdate(msg.session)

	case sessionCreatedMsg:
		if msg.err != nil {
			m.errMsg = "Error creating session: " + msg.err.Error()
			m.screen = ScreenHome
			return m, nil
		}
		m.session = msg.session
		m.isHost = true
		m.screen = ScreenWaiting
		m.errMsg = ""
		return m, pollSessionCmd(m.supabase, m.session.ID)

	case sessionJoinedMsg:
		if msg.err != nil {
			m.errMsg = "Error joining: " + msg.err.Error()
			m.screen = ScreenJoin
			return m, nil
		}
		m.session = msg.session
		m.isHost = false
		m.screen = ScreenLobby
		m.errMsg = ""
		return m, nil

	case roundStartedMsg:
		if msg.err != nil {
			m.errMsg = "Error starting round: " + msg.err.Error()
			return m, nil
		}
		m.session = msg.session
		return m.applyTimerFromSession()

	case actionDoneMsg:
		if msg.err != nil {
			m.errMsg = msg.err.Error()
			return m, nil
		}
		m.session = msg.session
		return m, nil

	case tea.KeyMsg:
		// Global quit handler — always active regardless of screen
		if msg.String() == "ctrl+c" || msg.String() == "ctrl+C" {
			m.cleanupSession()
			return m, tea.Quit
		}
		return m.handleKey(msg)

	case tea.MouseMsg:
		if msg.Action == tea.MouseActionPress && msg.Button == tea.MouseButtonLeft {
			for _, btn := range m.buttons {
				if msg.Y >= btn.y1 && msg.Y <= btn.y2 &&
					msg.X >= btn.x1 && msg.X <= btn.x2 {
					return m.handleButtonClick(btn.label)
				}
			}
		}
		return m, nil
	}

	return m, nil
}

func (m Model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	key := strings.ToLower(msg.String())

	switch m.screen {

	case ScreenHome:
		switch key {
		case "q", "ctrl+c":
			m.cleanupSession()
			return m, tea.Quit
		case "n":
			m.errMsg = ""
			return m, m.createSessionCmd()
		case "j":
			m.screen = ScreenJoin
			m.codeInput = ""
			m.errMsg = ""
			return m, nil
		case "s":
			m.screen = ScreenSolo
			m.soloPhase = PhaseWork
			m.soloStart = time.Now()
			m.soloElapsed = 0
			m.soloPaused = false
			m.soloRound = 1
			m.errMsg = ""
			return m, nil
		}

	case ScreenJoin:
		switch key {
		case "q", "ctrl+c", "esc":
			m.screen = ScreenHome
			return m, nil
		case "enter":
			if len(m.codeInput) == 4 {
				return m, m.joinSessionCmd(m.codeInput)
			}
		case "backspace":
			if len(m.codeInput) > 0 {
				m.codeInput = m.codeInput[:len(m.codeInput)-1]
			}
		default:
			if len(msg.Runes) == 1 && len(m.codeInput) < 4 {
				ch := strings.ToUpper(string(msg.Runes[0]))
				if ch >= "A" && ch <= "Z" {
					m.codeInput += ch
				}
			}
		}

	case ScreenWaiting:
		switch key {
		case "q":
			m.cleanupSession()
			return m, tea.Quit
		case "b", "esc":
			m.cleanupSession()
			m.session = nil
			m.isHost = false
			m.screen = ScreenHome
			return m, nil
		}

	case ScreenLobby:
		switch key {
		case "q", "ctrl+c":
			m.cleanupSession()
			return m, tea.Quit
		case "s":
			// Host can start the round
			if m.isHost {
				return m, m.startRoundCmd()
			}
		}

	case ScreenActive:
		switch key {
		case "q", "ctrl+c":
			m.cleanupSession()
			return m, tea.Quit
		case "p":
			if m.timer.CanDeclare() {
				return m, m.declareCmd()
			}
		case "g":
			if m.timer.CanGiveUp() {
				return m, m.giveUpCmd()
			}
		}

	case ScreenBreak:
		switch key {
		case "q", "ctrl+c":
			m.cleanupSession()
			return m, tea.Quit
		}

	case ScreenResult:
		switch key {
		case "q", "ctrl+c":
			m.cleanupSession()
			return m, tea.Quit
		case "n":
			m.screen = ScreenHome
			m.session = nil
			return m, nil
		}

	case ScreenSolo:
		switch key {
		case "q":
			m.screen = ScreenSoloDone
			return m, nil
		case "ctrl+c":
			return m, tea.Quit
		case "p":
			if m.soloPaused {
				// Resume: shift soloStart forward by paused duration
				m.soloStart = time.Now()
				m.soloPaused = false
			} else {
				// Pause: accumulate elapsed
				m.soloElapsed += time.Since(m.soloStart)
				m.soloPaused = true
			}
			return m, nil
		default:
			// Any key skips break (round was already incremented when work ended)
			if m.soloPhase == PhaseBreak {
				m.soloPhase = PhaseWork
				m.soloStart = time.Now()
				m.soloElapsed = 0
				m.soloPaused = false
				return m, nil
			}
		}

	case ScreenSoloDone:
		switch key {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "n":
			m.screen = ScreenHome
			return m, nil
		}
	}

	return m, nil
}

func (m Model) handleSessionUpdate(sess *Session) (tea.Model, tea.Cmd) {
	if sess == nil {
		return m, nil
	}
	prevState := ""
	if m.session != nil {
		prevState = m.session.State
	}
	m.session = sess

	switch sess.State {
	case "waiting":
		// Still waiting
	case "lobby":
		if m.screen == ScreenWaiting {
			m.screen = ScreenLobby
		}
	case "active":
		if prevState != "active" || m.screen == ScreenLobby || m.screen == ScreenBreak {
			return m.applyTimerFromSession()
		}
	case "break":
		if prevState != "break" {
			m.screen = ScreenBreak
			// Set break timer
			var startedAt time.Time
			if sess.TimerStartedAt != nil {
				parsed, err := time.Parse(time.RFC3339Nano, *sess.TimerStartedAt)
				if err == nil {
					startedAt = parsed
				}
			}
			m.timer = TimerState{
				Phase:       PhaseBreak,
				StartedAt:   startedAt,
				Round:       sess.Round,
				TotalRounds: TotalRounds,
			}
		}
	case "finished":
		m.screen = ScreenResult
	}

	return m, nil
}

func (m Model) applyTimerFromSession() (tea.Model, tea.Cmd) {
	if m.session == nil {
		return m, nil
	}
	var startedAt time.Time
	if m.session.TimerStartedAt != nil {
		parsed, err := time.Parse(time.RFC3339Nano, *m.session.TimerStartedAt)
		if err == nil {
			startedAt = parsed
		}
	}
	m.timer = NewTimerState(startedAt, m.session.Round)
	m.screen = ScreenActive
	return m, nil
}

func (m Model) handleTimerExpired() (tea.Model, tea.Cmd) {
	// Score: count round if declared and not gave up
	if m.session == nil {
		return m, nil
	}
	// Trigger round-end tomato explosion (~7 frames × 150ms ≈ 1s)
	m.explodeTimer = 7

	iDeclared := (m.isHost && m.session.HostDeclared) || (!m.isHost && m.session.GuestDeclared)
	iGaveUp := (m.isHost && m.session.HostGaveUp) || (!m.isHost && m.session.GuestGaveUp)

	myScore := 0
	partnerScore := 0
	if m.isHost {
		myScore = m.session.HostScore
		partnerScore = m.session.GuestScore
	} else {
		myScore = m.session.GuestScore
		partnerScore = m.session.HostScore
	}

	if iDeclared && !iGaveUp {
		myScore++
	}

	// Check if partner also deserves a point (for display)
	partnerDeclared := (!m.isHost && m.session.HostDeclared) || (m.isHost && m.session.GuestDeclared)
	partnerGaveUp := (!m.isHost && m.session.HostGaveUp) || (m.isHost && m.session.GuestGaveUp)
	if partnerDeclared && !partnerGaveUp {
		partnerScore++
	}

	isLastRound := m.session.Round >= TotalRounds

	if m.isHost {
		updates := map[string]interface{}{
			"host_score": myScore,
			"guest_score": partnerScore,
		}
		if isLastRound {
			updates["state"] = "finished"
		} else {
			updates["state"] = "break"
			now := time.Now().UTC().Format(time.RFC3339Nano)
			updates["timer_started_at"] = now
		}
		cmd := func() tea.Msg {
			sess, err := m.supabase.UpdateSession(m.session.ID, updates)
			return actionDoneMsg{session: sess, err: err}
		}
		m.screen = ScreenBreak
		m.timer = TimerState{
			Phase:       PhaseBreak,
			StartedAt:   time.Now(),
			Round:       m.session.Round,
			TotalRounds: TotalRounds,
		}
		return m, cmd
	}

	// Guest just transitions screen; host drives state
	m.screen = ScreenBreak
	return m, pollSessionCmd(m.supabase, m.session.ID)
}

func (m Model) handleBreakExpired() (tea.Model, tea.Cmd) {
	if m.session == nil {
		return m, nil
	}
	if m.isHost {
		nextRound := m.session.Round + 1
		return m, func() tea.Msg {
			sess, err := m.supabase.StartRound(m.session.ID, nextRound)
			return roundStartedMsg{session: sess, err: err}
		}
	}
	m.screen = ScreenLobby
	return m, pollSessionCmd(m.supabase, m.session.ID)
}

// Commands
func (m Model) createSessionCmd() tea.Cmd {
	return func() tea.Msg {
		sess, err := m.supabase.CreateSession(m.playerID)
		return sessionCreatedMsg{session: sess, err: err}
	}
}

func (m Model) joinSessionCmd(code string) tea.Cmd {
	return func() tea.Msg {
		sess, err := m.supabase.GetSessionByCode(code)
		if err != nil {
			return sessionJoinedMsg{err: err}
		}
		if sess.State != "waiting" {
			return sessionJoinedMsg{err: fmt.Errorf("session is busy or ended")}
		}
		joined, err := m.supabase.JoinSession(sess.ID, m.playerID)
		return sessionJoinedMsg{session: joined, err: err}
	}
}

func (m Model) startRoundCmd() tea.Cmd {
	return func() tea.Msg {
		round := 1
		if m.session != nil {
			round = m.session.Round
		}
		sess, err := m.supabase.StartRound(m.session.ID, round)
		return roundStartedMsg{session: sess, err: err}
	}
}

func (m Model) declareCmd() tea.Cmd {
	return func() tea.Msg {
		sess, err := m.supabase.Declare(m.session.ID, m.isHost)
		return actionDoneMsg{session: sess, err: err}
	}
}

func (m Model) giveUpCmd() tea.Cmd {
	return func() tea.Msg {
		sess, err := m.supabase.GiveUp(m.session.ID, m.isHost)
		return actionDoneMsg{session: sess, err: err}
	}
}

// handleButtonClick dispatches a mouse click on a named button to the same
// logic used by the keyboard handler.
func (m Model) handleButtonClick(label string) (tea.Model, tea.Cmd) {
	switch label {
	case "new_session":
		m.errMsg = ""
		return m, m.createSessionCmd()
	case "join_screen":
		m.screen = ScreenJoin
		m.codeInput = ""
		m.errMsg = ""
		return m, nil
	case "solo":
		m.screen = ScreenSolo
		m.soloPhase = PhaseWork
		m.soloStart = time.Now()
		m.soloElapsed = 0
		m.soloPaused = false
		m.soloRound = 1
		m.errMsg = ""
		return m, nil
	case "quit":
		m.cleanupSession()
		return m, tea.Quit
	case "back":
		m.cleanupSession()
		m.session = nil
		m.isHost = false
		m.screen = ScreenHome
		return m, nil
	case "join_submit":
		if len(m.codeInput) == 4 {
			return m, m.joinSessionCmd(m.codeInput)
		}
		return m, nil
	case "start_round":
		if m.isHost {
			return m, m.startRoundCmd()
		}
		return m, nil
	case "working":
		if m.timer.CanDeclare() {
			return m, m.declareCmd()
		}
		return m, nil
	case "giveup":
		if m.timer.CanGiveUp() {
			return m, m.giveUpCmd()
		}
		return m, nil
	case "pause_resume":
		if m.soloPaused {
			m.soloStart = time.Now()
			m.soloPaused = false
		} else {
			m.soloElapsed += time.Since(m.soloStart)
			m.soloPaused = true
		}
		return m, nil
	case "skip_break":
		if m.soloPhase == PhaseBreak {
			m.soloPhase = PhaseWork
			m.soloStart = time.Now()
			m.soloElapsed = 0
			m.soloPaused = false
		}
		return m, nil
	case "solo_quit":
		m.screen = ScreenSoloDone
		return m, nil
	case "new_home":
		m.screen = ScreenHome
		m.session = nil
		return m, nil
	}
	return m, nil
}

// View
func (m Model) View() string {
	switch m.screen {
	case ScreenHome:
		return m.viewHome()
	case ScreenWaiting:
		return m.viewWaiting()
	case ScreenJoin:
		return m.viewJoin()
	case ScreenLobby:
		return m.viewLobby()
	case ScreenActive:
		return m.viewActive()
	case ScreenBreak:
		return m.viewBreak()
	case ScreenResult:
		return m.viewResult()
	case ScreenSolo:
		return m.viewSolo()
	case ScreenSoloDone:
		return m.viewSoloDone()
	}
	return ""
}

// centerOffsets returns the (paddingTop, paddingLeft) added by centerView for
// a given content string, so callers can shift button regions accordingly.
func (m Model) centerOffsets(content string) (int, int) {
	if m.width == 0 {
		return 0, 0
	}
	lines := strings.Split(content, "\n")
	contentH := len(lines)
	contentW := 0
	for _, l := range lines {
		w := lipgloss.Width(l)
		if w > contentW {
			contentW = w
		}
	}
	paddingTop := (m.height - contentH) / 2
	if paddingTop < 0 {
		paddingTop = 0
	}
	paddingLeft := (m.width - contentW) / 2
	if paddingLeft < 0 {
		paddingLeft = 0
	}
	return paddingTop, paddingLeft
}

func (m Model) centerView(content string) string {
	if m.width == 0 {
		return content
	}
	paddingTop, paddingLeft := m.centerOffsets(content)

	topPad := strings.Repeat("\n", paddingTop)
	leftPad := strings.Repeat(" ", paddingLeft)

	lines := strings.Split(content, "\n")
	result := topPad
	for _, l := range lines {
		result += leftPad + l + "\n"
	}
	return result
}

// registerButtons registers clickable button regions for a view.
// lineButtons maps content-relative line number → (label, rendered text).
// topOff/leftOff are the centering offsets from centerOffsets().
func (m *Model) registerButtons(lineButtons map[int][]struct{ label, text string }, topOff, leftOff int) {
	for lineNum, btns := range lineButtons {
		absY := topOff + lineNum
		// Track horizontal cursor position within the line to find each button
		col := leftOff
		for _, btn := range btns {
			w := lipgloss.Width(btn.text)
			m.buttons = append(m.buttons, buttonRegion{
				label: btn.label,
				y1:    absY, y2: absY,
				x1: col, x2: col + w - 1,
			})
			col += w + 2 // approximate spacing between buttons on same line
		}
	}
}

func (m *Model) viewHome() string {
	m.buttons = nil
	btnNew := renderButton("New session")
	btnJoin := renderButton("Join session")
	btnSolo := renderButton("Solo mode")
	btnQuit := renderButton("Quit")

	var lines []string
	// ASCII tomato logo (3 lines)
	for _, l := range strings.Split(TomatoLogo, "\n") {
		lines = append(lines, styleTitle.Render(l))
	}
	lines = append(lines, styleTitle.Render("  Pomodare"))  // line 3
	lines = append(lines, styleMuted.Render(Tagline))       // line 4
	lines = append(lines, "")                               // line 5
	lines = append(lines, btnNew)                           // line 6
	lines = append(lines, btnJoin)                          // line 7
	lines = append(lines, btnSolo)                          // line 8
	lines = append(lines, "")                               // line 9
	if m.errMsg != "" {
		lines = append(lines, styleWarning.Render(truncate(m.errMsg, 46)))
		lines = append(lines, btnQuit) // line 11
	} else {
		lines = append(lines, btnQuit) // line 10
	}

	content := strings.Join(lines, "\n")
	topOff, leftOff := m.centerOffsets(content)

	quitLine := 10
	if m.errMsg != "" {
		quitLine = 11
	}
	m.registerButtons(map[int][]struct{ label, text string }{
		6:        {{label: "new_session", text: btnNew}},
		7:        {{label: "join_screen", text: btnJoin}},
		8:        {{label: "solo", text: btnSolo}},
		quitLine: {{label: "quit", text: btnQuit}},
	}, topOff, leftOff)

	return m.centerView(content)
}

func (m *Model) viewWaiting() string {
	m.buttons = nil
	code := "????"
	if m.session != nil {
		code = m.session.Code
	}
	frame := TomatoFrames[m.spinnerIdx]
	btnBack := renderButton("Back")
	btnQuit := renderButton("Quit")

	var lines []string
	for _, l := range strings.Split(frame, "\n") {
		lines = append(lines, styleTitle.Render(l))
	}
	// frame = 3 lines (0,1,2)
	lines = append(lines, "")                                     // 3
	lines = append(lines, "Your code: "+styleCode.Render(code))  // 4
	lines = append(lines, "")                                     // 5
	lines = append(lines, styleMuted.Render("Waiting for partner...")) // 6
	lines = append(lines, "")                                     // 7
	lines = append(lines, btnBack+"  "+btnQuit)                   // 8

	content := strings.Join(lines, "\n")
	topOff, leftOff := m.centerOffsets(content)
	m.registerButtons(map[int][]struct{ label, text string }{
		8: {
			{label: "back", text: btnBack},
			{label: "quit", text: btnQuit},
		},
	}, topOff, leftOff)

	return m.centerView(content)
}

func (m *Model) viewJoin() string {
	m.buttons = nil
	codeDisplay := m.codeInput + strings.Repeat("_", 4-len(m.codeInput))
	btnJoin := renderButton("Join")
	btnBack := renderButton("Back")
	btnQuit := renderButton("Quit")

	var lines []string
	lines = append(lines, styleTitle.Render("Pomodare 🍅")) // 0
	lines = append(lines, "")                               // 1
	lines = append(lines, "Kod: "+styleCode.Render(codeDisplay)) // 2
	lines = append(lines, "")                               // 3
	if m.errMsg != "" {
		lines = append(lines, styleWarning.Render(truncate(m.errMsg, 46))) // 4
	} else {
		lines = append(lines, styleMuted.Render("Enter 4 letters and press Enter")) // 4
	}
	lines = append(lines, "")                               // 5
	lines = append(lines, btnJoin+"  "+btnBack+"  "+btnQuit) // 6

	content := strings.Join(lines, "\n")
	topOff, leftOff := m.centerOffsets(content)
	m.registerButtons(map[int][]struct{ label, text string }{
		6: {
			{label: "join_submit", text: btnJoin},
			{label: "back", text: btnBack},
			{label: "quit", text: btnQuit},
		},
	}, topOff, leftOff)

	return m.centerView(content)
}

func (m *Model) viewLobby() string {
	m.buttons = nil
	role := "guest"
	if m.isHost {
		role = "host"
	}
	frame := TomatoFrames[m.spinnerIdx]
	btnQuit := renderButton("Quit")

	var lines []string
	lines = append(lines, "Connected! ("+role+")") // 0
	lines = append(lines, "")                      // 1

	lineButtons := map[int][]struct{ label, text string }{}

	if m.isHost {
		btnStart := renderKeyButton("S", "Start round")
		lines = append(lines, btnStart) // 2
		lines = append(lines, "")       // 3
		lines = append(lines, btnQuit)  // 4
		lineButtons[2] = []struct{ label, text string }{{label: "start_round", text: btnStart}}
		lineButtons[4] = []struct{ label, text string }{{label: "quit", text: btnQuit}}
	} else {
		for _, l := range strings.Split(frame, "\n") {
			lines = append(lines, styleTitle.Render(l))
		}
		// frame lines 2,3,4
		lines = append(lines, "")                              // 5
		lines = append(lines, styleMuted.Render("Waiting for host...")) // 6
		lines = append(lines, "")                              // 7
		lines = append(lines, btnQuit)                         // 8
		lineButtons[8] = []struct{ label, text string }{{label: "quit", text: btnQuit}}
	}

	content := strings.Join(lines, "\n")
	topOff, leftOff := m.centerOffsets(content)
	m.registerButtons(lineButtons, topOff, leftOff)

	return m.centerView(content)
}

func (m Model) viewActive() string {
	if m.session == nil {
		return m.centerView("Loading...")
	}

	// Round-end explosion flash
	if m.explodeTimer > 0 {
		var lines []string
		for _, l := range strings.Split(TomatoExplode, "\n") {
			lines = append(lines, styleWarning.Render(l))
		}
		lines = append(lines, "")
		lines = append(lines, styleMuted.Render("Round over!"))
		return m.centerView(strings.Join(lines, "\n"))
	}

	round := m.session.Round
	remaining := m.timer.Remaining()
	progress := m.timer.Progress()
	timeStr := FormatDuration(remaining)

	myDeclared := (m.isHost && m.session.HostDeclared) || (!m.isHost && m.session.GuestDeclared)
	myGaveUp := (m.isHost && m.session.HostGaveUp) || (!m.isHost && m.session.GuestGaveUp)
	partnerDeclared := (!m.isHost && m.session.HostDeclared) || (m.isHost && m.session.GuestDeclared)
	partnerGaveUp := (!m.isHost && m.session.HostGaveUp) || (m.isHost && m.session.GuestGaveUp)

	myStatus := playerStatusCompact(myDeclared, myGaveUp)
	partnerStatus := playerStatusCompact(partnerDeclared, partnerGaveUp)

	progressBar := renderProgressBar(progress, 22)

	var lines []string
	lines = append(lines, fmt.Sprintf("🍅 Round %d/%d  |  %s", round, TotalRounds, styleTimer.Render(timeStr)))
	lines = append(lines, progressBar)
	lines = append(lines, "")
	lines = append(lines, "You: "+myStatus+"  Partner: "+partnerStatus)
	lines = append(lines, "")

	var ctrlParts []string
	if m.timer.CanDeclare() && !myDeclared {
		ctrlParts = append(ctrlParts, renderKeyButton("P", "Working"))
	}
	if m.timer.CanGiveUp() {
		ctrlParts = append(ctrlParts, renderButton("Give up"))
	}
	ctrlParts = append(ctrlParts, renderButton("Quit"))
	lines = append(lines, strings.Join(ctrlParts, "  "))

	return m.centerView(strings.Join(lines, "\n"))
}

func (m Model) viewBreak() string {
	remaining := m.timer.Remaining()
	timeStr := FormatDuration(remaining)
	progress := m.timer.Progress()
	progressBar := renderProgressBar(progress, 22)
	frame := TomatoFrames[m.spinnerIdx]

	var lines []string
	lines = append(lines, fmt.Sprintf("☕ Break  |  %s", styleTimer.Render(timeStr)))
	lines = append(lines, progressBar)
	lines = append(lines, "")
	for _, l := range strings.Split(frame, "\n") {
		lines = append(lines, styleMuted.Render(l))
	}
	lines = append(lines, "")
	lines = append(lines, styleMuted.Render("Next round in a moment..."))
	lines = append(lines, "")
	lines = append(lines, renderButton("Quit"))
	return m.centerView(strings.Join(lines, "\n"))
}

func (m Model) viewResult() string {
	myScore := 0
	partnerScore := 0
	if m.session != nil {
		if m.isHost {
			myScore = m.session.HostScore
			partnerScore = m.session.GuestScore
		} else {
			myScore = m.session.GuestScore
			partnerScore = m.session.HostScore
		}
	}

	var lines []string
	lines = append(lines, "🎉 Session over!")
	lines = append(lines, "")
	lines = append(lines, fmt.Sprintf("You:     %s", styleSuccess.Render(fmt.Sprintf("%d/%d rounds", myScore, TotalRounds))))
	lines = append(lines, fmt.Sprintf("Partner: %s", styleMuted.Render(fmt.Sprintf("%d/%d rounds", partnerScore, TotalRounds))))
	lines = append(lines, "")
	lines = append(lines, renderButton("New session")+"  "+renderButton("Quit"))
	return m.centerView(strings.Join(lines, "\n"))
}

func (m Model) soloElapsedTotal() time.Duration {
	if m.soloPaused {
		return m.soloElapsed
	}
	return m.soloElapsed + time.Since(m.soloStart)
}

func (m Model) soloRemaining() time.Duration {
	phaseDur := WorkDuration
	if m.soloPhase == PhaseBreak {
		phaseDur = BreakDuration
	}
	rem := phaseDur - m.soloElapsedTotal()
	if rem < 0 {
		rem = 0
	}
	return rem
}

func (m Model) soloProgress() float64 {
	phaseDur := WorkDuration
	if m.soloPhase == PhaseBreak {
		phaseDur = BreakDuration
	}
	elapsed := m.soloElapsedTotal()
	if elapsed >= phaseDur {
		return 1.0
	}
	return float64(elapsed) / float64(phaseDur)
}

func (m Model) viewSolo() string {
	remaining := m.soloRemaining()
	timeStr := FormatDuration(remaining)
	progress := m.soloProgress()
	bar := renderProgressBar(progress, 20)

	var header string
	var lines []string

	switch {
	case m.soloPaused:
		header = fmt.Sprintf("⏸ Paused — Round %d", m.soloRound)
		lines = append(lines, styleTitle.Render(header))
		lines = append(lines, bar+"  "+styleTimer.Render(timeStr))
		lines = append(lines, "")
		lines = append(lines, renderKeyButton("P", "Resume")+"  "+renderButton("Quit"))
	case m.soloPhase == PhaseBreak:
		header = fmt.Sprintf("☕ Break — %s", FormatDuration(BreakDuration))
		lines = append(lines, styleTitle.Render(header))
		lines = append(lines, bar+"  "+styleTimer.Render(timeStr))
		lines = append(lines, "")
		lines = append(lines, styleMuted.Render("Press any key to skip break"))
		lines = append(lines, renderButton("Quit"))
	default:
		header = fmt.Sprintf("🍅 Solo — Round %d", m.soloRound)
		lines = append(lines, styleTitle.Render(header))
		lines = append(lines, bar+"  "+styleTimer.Render(timeStr))
		lines = append(lines, "")
		lines = append(lines, renderKeyButton("P", "Pause")+"  "+renderButton("Quit"))
	}

	return m.centerView(strings.Join(lines, "\n"))
}

func (m Model) viewSoloDone() string {
	// soloRound was incremented when work ended, so completed rounds = soloRound - 1
	// unless we quit during work phase (soloRound is still the current one)
	// We track how many work phases completed: that's soloRound - 1 if currently in break/work after break
	// Simple approach: show soloRound - 1 if phase is work (quit mid-work), soloRound if quit during break
	completed := m.soloRound - 1
	if m.soloPhase == PhaseBreak {
		completed = m.soloRound - 1 // already incremented
	}
	if completed < 0 {
		completed = 0
	}

	var lines []string
	lines = append(lines, styleTitle.Render("Session complete"))
	lines = append(lines, fmt.Sprintf("Rounds: %s", styleSuccess.Render(fmt.Sprintf("%d", completed))))
	lines = append(lines, "")
	lines = append(lines, renderButton("New session")+"  "+renderButton("Quit"))
	return m.centerView(strings.Join(lines, "\n"))
}

func playerStatus(declared, gaveUp bool) string {
	return playerStatusCompact(declared, gaveUp)
}

func playerStatusCompact(declared, gaveUp bool) string {
	if gaveUp {
		return styleWarning.Render("❌")
	}
	if declared {
		return styleSuccess.Render("✅")
	}
	return styleMuted.Render("⏳")
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-1] + "…"
}
