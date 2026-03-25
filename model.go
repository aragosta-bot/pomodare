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

// Model is the main application state
type Model struct {
	screen     Screen
	supabase   *SupabaseClient
	playerID   string
	isHost     bool
	session    *Session
	timer      TimerState
	codeInput  string
	errMsg     string
	pollTicker int
	spinnerIdx int
	width      int
	height     int
}

var spinnerFrames = []string{"⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"}

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
		m.supabase.DeleteSession(m.session.ID)
	}
}

func (m Model) Init() tea.Cmd {
	return tickCmd()
}

func tickCmd() tea.Cmd {
	return tea.Tick(500*time.Millisecond, func(t time.Time) tea.Msg {
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
		m.spinnerIdx = (m.spinnerIdx + 1) % len(spinnerFrames)
		cmds := []tea.Cmd{tickCmd()}

		// Poll for session updates every ~3 seconds (6 ticks at 500ms)
		if m.session != nil {
			m.pollTicker++
			if m.pollTicker >= 6 {
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

		return m, tea.Batch(cmds...)

	case sessionPollMsg:
		if msg.err != nil {
			m.errMsg = msg.err.Error()
			return m, nil
		}
		return m.handleSessionUpdate(msg.session)

	case sessionCreatedMsg:
		if msg.err != nil {
			m.errMsg = "Błąd tworzenia sesji: " + msg.err.Error()
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
			m.errMsg = "Błąd dołączania: " + msg.err.Error()
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
			m.errMsg = "Błąd startu rundy: " + msg.err.Error()
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
		case "q", "ctrl+c":
			m.cleanupSession()
			return m, tea.Quit
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
			return sessionJoinedMsg{err: fmt.Errorf("sesja jest zajęta lub zakończona")}
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
	}
	return ""
}

func (m Model) centerView(content string) string {
	if m.width == 0 {
		return content
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

	topPad := strings.Repeat("\n", paddingTop)
	leftPad := strings.Repeat(" ", paddingLeft)

	result := topPad
	for _, l := range lines {
		result += leftPad + l + "\n"
	}
	return result
}

func (m Model) viewHome() string {
	var lines []string
	lines = append(lines, styleTitle.Render("Pomodare 🍅"))
	lines = append(lines, "")
	lines = append(lines, styleKeyHighlight.Render("[N]")+" Nowa sesja")
	lines = append(lines, styleKeyHighlight.Render("[J]")+" Dołącz do sesji")
	lines = append(lines, "")
	if m.errMsg != "" {
		lines = append(lines, styleWarning.Render(truncate(m.errMsg, 46)))
	}
	lines = append(lines, styleKey.Render("[Q] Wyjdź"))
	return m.centerView(strings.Join(lines, "\n"))
}

func (m Model) viewWaiting() string {
	code := "????"
	if m.session != nil {
		code = m.session.Code
	}
	spinner := spinnerFrames[m.spinnerIdx]
	var lines []string
	lines = append(lines, styleTitle.Render("Pomodare 🍅"))
	lines = append(lines, "")
	lines = append(lines, "Twój kod: "+styleCode.Render(code))
	lines = append(lines, "")
	lines = append(lines, styleMuted.Render("Czekam na partnera... "+spinner))
	lines = append(lines, "")
	lines = append(lines, styleKey.Render("[Q] Wyjdź"))
	return m.centerView(strings.Join(lines, "\n"))
}

func (m Model) viewJoin() string {
	codeDisplay := m.codeInput + strings.Repeat("_", 4-len(m.codeInput))
	var lines []string
	lines = append(lines, styleTitle.Render("Pomodare 🍅"))
	lines = append(lines, "")
	lines = append(lines, "Kod: "+styleCode.Render(codeDisplay))
	lines = append(lines, "")
	if m.errMsg != "" {
		lines = append(lines, styleWarning.Render(truncate(m.errMsg, 46)))
	} else {
		lines = append(lines, styleMuted.Render("Wpisz 4 litery i Enter"))
	}
	lines = append(lines, "")
	lines = append(lines, styleKey.Render("[Enter] Dołącz  [Esc] Wróć  [Q] Wyjdź"))
	return m.centerView(strings.Join(lines, "\n"))
}

func (m Model) viewLobby() string {
	role := "gość"
	if m.isHost {
		role = "host"
	}
	spinner := spinnerFrames[m.spinnerIdx]
	var lines []string
	lines = append(lines, styleTitle.Render("Pomodare 🍅"))
	lines = append(lines, "")
	lines = append(lines, "Połączono! ("+role+")")
	lines = append(lines, "")
	if m.isHost {
		lines = append(lines, styleKeyHighlight.Render("[S]")+" Start rundy")
	} else {
		lines = append(lines, styleMuted.Render("Czekam na hosta... "+spinner))
	}
	lines = append(lines, "")
	lines = append(lines, styleKey.Render("[Q] Wyjdź"))
	return m.centerView(strings.Join(lines, "\n"))
}

func (m Model) viewActive() string {
	if m.session == nil {
		return m.centerView("Ładowanie...")
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
	lines = append(lines, fmt.Sprintf("🍅 Runda %d/%d  |  %s", round, TotalRounds, styleTimer.Render(timeStr)))
	lines = append(lines, progressBar)
	lines = append(lines, "")
	lines = append(lines, "Ty: "+myStatus+"  Partner: "+partnerStatus)
	lines = append(lines, "")

	var ctrlParts []string
	if m.timer.CanDeclare() && !myDeclared {
		ctrlParts = append(ctrlParts, styleKeyHighlight.Render("[P]")+" Pracuję")
	}
	if m.timer.CanGiveUp() {
		ctrlParts = append(ctrlParts, styleKeyHighlight.Render("[G]")+" Rezygnuj")
	}
	ctrlParts = append(ctrlParts, styleKeyHighlight.Render("[Q]")+" Wyjdź")
	lines = append(lines, strings.Join(ctrlParts, "  "))

	return m.centerView(strings.Join(lines, "\n"))
}

func (m Model) viewBreak() string {
	remaining := m.timer.Remaining()
	timeStr := FormatDuration(remaining)
	progress := m.timer.Progress()
	progressBar := renderProgressBar(progress, 22)
	spinner := spinnerFrames[m.spinnerIdx]

	var lines []string
	lines = append(lines, fmt.Sprintf("☕ Przerwa  |  %s", styleTimer.Render(timeStr)))
	lines = append(lines, progressBar)
	lines = append(lines, "")
	lines = append(lines, styleMuted.Render("Następna runda za chwilę... "+spinner))
	lines = append(lines, "")
	lines = append(lines, styleKey.Render("[Q] Wyjdź"))
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
	lines = append(lines, "🎉 Sesja zakończona!")
	lines = append(lines, "")
	lines = append(lines, fmt.Sprintf("Ty:      %s", styleSuccess.Render(fmt.Sprintf("%d/%d rund", myScore, TotalRounds))))
	lines = append(lines, fmt.Sprintf("Partner: %s", styleMuted.Render(fmt.Sprintf("%d/%d rund", partnerScore, TotalRounds))))
	lines = append(lines, "")
	lines = append(lines, styleKeyHighlight.Render("[N]")+" Nowa sesja  "+styleKeyHighlight.Render("[Q]")+" Wyjdź")
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
