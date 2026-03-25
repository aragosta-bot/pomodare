package main

import (
	"time"
)

const (
	WorkDuration  = 25 * time.Minute
	BreakDuration = 5 * time.Minute
	TotalRounds   = 5
	// Must declare working within first 5 minutes
	DeclareDeadline = 5 * time.Minute
	// Giving up after this point doesn't count (must give up before 20 min mark)
	GiveUpDeadline = 20 * time.Minute
)

type Phase int

const (
	PhaseWork  Phase = iota
	PhaseBreak Phase = iota
)

type TimerState struct {
	Phase          Phase
	StartedAt      time.Time
	Round          int // 1-indexed
	TotalRounds    int
}

func NewTimerState(startedAt time.Time, round int) TimerState {
	return TimerState{
		Phase:       PhaseWork,
		StartedAt:   startedAt,
		Round:       round,
		TotalRounds: TotalRounds,
	}
}

func (t TimerState) Elapsed() time.Duration {
	if t.StartedAt.IsZero() {
		return 0
	}
	return time.Since(t.StartedAt)
}

func (t TimerState) Remaining() time.Duration {
	duration := WorkDuration
	if t.Phase == PhaseBreak {
		duration = BreakDuration
	}
	remaining := duration - t.Elapsed()
	if remaining < 0 {
		return 0
	}
	return remaining
}

func (t TimerState) Progress() float64 {
	duration := WorkDuration
	if t.Phase == PhaseBreak {
		duration = BreakDuration
	}
	elapsed := t.Elapsed()
	if elapsed >= duration {
		return 1.0
	}
	return float64(elapsed) / float64(duration)
}

func (t TimerState) IsExpired() bool {
	return t.Remaining() == 0
}

func (t TimerState) CanDeclare() bool {
	return t.Phase == PhaseWork && t.Elapsed() <= DeclareDeadline
}

func (t TimerState) CanGiveUp() bool {
	return t.Phase == PhaseWork && t.Elapsed() < GiveUpDeadline
}

func FormatDuration(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	minutes := int(d.Minutes())
	seconds := int(d.Seconds()) % 60
	return formatTime(minutes, seconds)
}

func formatTime(minutes, seconds int) string {
	m := ""
	s := ""
	if minutes < 10 {
		m = "0"
	}
	m += itoa(minutes)
	if seconds < 10 {
		s = "0"
	}
	s += itoa(seconds)
	return m + ":" + s
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	result := ""
	for n > 0 {
		result = string(rune('0'+n%10)) + result
		n /= 10
	}
	return result
}
