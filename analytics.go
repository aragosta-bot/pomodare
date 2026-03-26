package main

import (
	"runtime"

	"github.com/posthog/posthog-go"
)

var phClient posthog.Client

func initAnalytics(userID string) {
	client, err := posthog.NewWithConfig(
		"phc_JPOd4CiFFRPx7otsFIETy1Yqox99WjZPDkbyZVrTKlc",
		posthog.Config{
			Endpoint: "https://eu.i.posthog.com",
		},
	)
	if err != nil {
		return
	}
	phClient = client
	trackEvent(userID, "app_started", map[string]interface{}{
		"platform": runtime.GOOS,
		"arch":     runtime.GOARCH,
	})
}

func trackEvent(userID, event string, props map[string]interface{}) {
	if phClient == nil {
		return
	}
	p := posthog.NewProperties().Set("app", "pomodare")
	for k, v := range props {
		p.Set(k, v)
	}
	phClient.Enqueue(posthog.Capture{
		DistinctId: userID,
		Event:      event,
		Properties: p,
	})
}

func closeAnalytics() {
	if phClient != nil {
		phClient.Close()
	}
}
