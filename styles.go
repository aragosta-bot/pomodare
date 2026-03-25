package main

import "github.com/charmbracelet/lipgloss"

var (
	colorPrimary   = lipgloss.Color("#FF6B6B")
	colorSecondary = lipgloss.Color("#4ECDC4")
	colorMuted     = lipgloss.Color("#666666")
	colorSuccess   = lipgloss.Color("#95E1D3")
	colorWarning   = lipgloss.Color("#F38181")
	colorText      = lipgloss.Color("#EEEEEE")

	styleBox = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colorPrimary).
			Padding(1, 2)

	styleTitle = lipgloss.NewStyle().
			Foreground(colorPrimary).
			Bold(true)

	styleTimer = lipgloss.NewStyle().
			Foreground(colorSecondary).
			Bold(true)

	styleCode = lipgloss.NewStyle().
			Foreground(colorSuccess).
			Bold(true).
			Background(lipgloss.Color("#1a1a2e")).
			Padding(0, 1)

	styleKey = lipgloss.NewStyle().
			Foreground(colorMuted)

	styleKeyHighlight = lipgloss.NewStyle().
				Foreground(colorText).
				Bold(true)

	styleMuted = lipgloss.NewStyle().
			Foreground(colorMuted)

	styleSuccess = lipgloss.NewStyle().
			Foreground(colorSuccess)

	styleWarning = lipgloss.NewStyle().
			Foreground(colorWarning)

	styleProgressFill = lipgloss.NewStyle().
				Foreground(colorPrimary)

	styleProgressEmpty = lipgloss.NewStyle().
				Foreground(colorMuted)
)

func renderProgressBar(percent float64, width int) string {
	filled := int(float64(width) * percent)
	if filled > width {
		filled = width
	}
	empty := width - filled

	bar := styleProgressFill.Render(repeatStr("█", filled))
	bar += styleProgressEmpty.Render(repeatStr("░", empty))
	return bar
}

func repeatStr(s string, n int) string {
	result := ""
	for i := 0; i < n; i++ {
		result += s
	}
	return result
}
