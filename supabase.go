package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

const (
	defaultSupabaseURL     = "https://alcijxissydvfemjblln.supabase.co"
	defaultSupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFsY2lqeGlzc3lkdmZlbWpibGxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzODA1NDksImV4cCI6MjA4OTk1NjU0OX0.8UDqM1QQofasGw1-shmfgXhkWiu8N4n52nn2QbD-LhA"
)

func getSupabaseURL() string {
	if v := os.Getenv("POMODARE_SUPABASE_URL"); v != "" {
		return v
	}
	return defaultSupabaseURL
}

func getSupabaseAnonKey() string {
	if v := os.Getenv("POMODARE_SUPABASE_ANON_KEY"); v != "" {
		return v
	}
	return defaultSupabaseAnonKey
}

// Session represents a Pomodare session in Supabase
type Session struct {
	ID           string     `json:"id"`
	Code         string     `json:"code"`
	State        string     `json:"state"`
	HostID       string     `json:"host_id"`
	GuestID      *string    `json:"guest_id"`
	Round        int        `json:"round"`
	TimerStartedAt *string  `json:"timer_started_at"`
	HostDeclared bool       `json:"host_declared"`
	GuestDeclared bool      `json:"guest_declared"`
	HostGaveUp   bool       `json:"host_gave_up"`
	GuestGaveUp  bool       `json:"guest_gave_up"`
	HostScore    int        `json:"host_score"`
	GuestScore   int        `json:"guest_score"`
	CreatedAt    string     `json:"created_at"`
	UpdatedAt    string     `json:"updated_at"`
}

type SupabaseClient struct {
	baseURL string
	apiKey  string
	client  *http.Client
}

func NewSupabaseClient() *SupabaseClient {
	return &SupabaseClient{
		baseURL: getSupabaseURL(),
		apiKey:  getSupabaseAnonKey(),
		client:  &http.Client{Timeout: 10 * time.Second},
	}
}

func (s *SupabaseClient) headers() map[string]string {
	return map[string]string{
		"apikey":        s.apiKey,
		"Authorization": "Bearer " + s.apiKey,
		"Content-Type":  "application/json",
		"Prefer":        "return=representation",
	}
}

func (s *SupabaseClient) doRequest(method, path string, body interface{}) ([]byte, int, error) {
	var reqBody io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return nil, 0, err
		}
		reqBody = bytes.NewReader(data)
	}

	req, err := http.NewRequest(method, s.baseURL+"/rest/v1/"+path, reqBody)
	if err != nil {
		return nil, 0, err
	}

	for k, v := range s.headers() {
		req.Header.Set(k, v)
	}

	resp, err := s.client.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, err
	}

	return data, resp.StatusCode, nil
}

// CreateSession creates a new session with a random 4-letter code
func (s *SupabaseClient) CreateSession(hostID string) (*Session, error) {
	code := generateCode()
	payload := map[string]interface{}{
		"code":           code,
		"state":          "waiting",
		"host_id":        hostID,
		"round":          1,
		"host_declared":  false,
		"guest_declared": false,
		"host_gave_up":   false,
		"guest_gave_up":  false,
		"host_score":     0,
		"guest_score":    0,
	}

	data, status, err := s.doRequest("POST", "sessions", payload)
	if err != nil {
		return nil, err
	}
	if status != 201 {
		return nil, fmt.Errorf("create session failed: %d %s", status, string(data))
	}

	var sessions []Session
	if err := json.Unmarshal(data, &sessions); err != nil {
		return nil, err
	}
	if len(sessions) == 0 {
		return nil, fmt.Errorf("no session returned")
	}
	return &sessions[0], nil
}

// GetSessionByCode fetches a session by its 4-letter code
func (s *SupabaseClient) GetSessionByCode(code string) (*Session, error) {
	data, status, err := s.doRequest("GET", "sessions?code=eq."+strings.ToUpper(code)+"&limit=1", nil)
	if err != nil {
		return nil, err
	}
	if status != 200 {
		return nil, fmt.Errorf("get session failed: %d", status)
	}

	var sessions []Session
	if err := json.Unmarshal(data, &sessions); err != nil {
		return nil, err
	}
	if len(sessions) == 0 {
		return nil, fmt.Errorf("session not found")
	}
	return &sessions[0], nil
}

// GetSession fetches a session by ID
func (s *SupabaseClient) GetSession(id string) (*Session, error) {
	data, status, err := s.doRequest("GET", "sessions?id=eq."+id+"&limit=1", nil)
	if err != nil {
		return nil, err
	}
	if status != 200 {
		return nil, fmt.Errorf("get session failed: %d", status)
	}

	var sessions []Session
	if err := json.Unmarshal(data, &sessions); err != nil {
		return nil, err
	}
	if len(sessions) == 0 {
		return nil, fmt.Errorf("session not found")
	}
	return &sessions[0], nil
}

// JoinSession sets guest_id on a waiting session
func (s *SupabaseClient) JoinSession(sessionID, guestID string) (*Session, error) {
	payload := map[string]interface{}{
		"guest_id": guestID,
		"state":    "lobby",
	}
	data, status, err := s.doRequest("PATCH", "sessions?id=eq."+sessionID, payload)
	if err != nil {
		return nil, err
	}
	if status != 200 {
		return nil, fmt.Errorf("join session failed: %d %s", status, string(data))
	}

	var sessions []Session
	if err := json.Unmarshal(data, &sessions); err != nil {
		return nil, err
	}
	if len(sessions) == 0 {
		return nil, fmt.Errorf("no session returned")
	}
	return &sessions[0], nil
}

// UpdateSession patches arbitrary fields on a session
func (s *SupabaseClient) UpdateSession(sessionID string, fields map[string]interface{}) (*Session, error) {
	data, status, err := s.doRequest("PATCH", "sessions?id=eq."+sessionID, fields)
	if err != nil {
		return nil, err
	}
	if status != 200 {
		return nil, fmt.Errorf("update session failed: %d %s", status, string(data))
	}

	var sessions []Session
	if err := json.Unmarshal(data, &sessions); err != nil {
		return nil, err
	}
	if len(sessions) == 0 {
		return nil, fmt.Errorf("no session returned")
	}
	return &sessions[0], nil
}

// StartRound sets timer_started_at and state=active (host only)
func (s *SupabaseClient) StartRound(sessionID string, round int) (*Session, error) {
	now := time.Now().UTC().Format(time.RFC3339Nano)
	return s.UpdateSession(sessionID, map[string]interface{}{
		"state":            "active",
		"timer_started_at": now,
		"round":            round,
		"host_declared":    false,
		"guest_declared":   false,
		"host_gave_up":     false,
		"guest_gave_up":    false,
	})
}

// Declare marks the player as working
func (s *SupabaseClient) Declare(sessionID string, isHost bool) (*Session, error) {
	field := "guest_declared"
	if isHost {
		field = "host_declared"
	}
	return s.UpdateSession(sessionID, map[string]interface{}{field: true})
}

// GiveUp marks the player as giving up
func (s *SupabaseClient) GiveUp(sessionID string, isHost bool) (*Session, error) {
	field := "guest_gave_up"
	if isHost {
		field = "host_gave_up"
	}
	return s.UpdateSession(sessionID, map[string]interface{}{field: true})
}

// generateCode creates a random 4-letter code (CVCV pattern for pronounceability)
func generateCode() string {
	consonants := []byte("BCDFGHJKLMNPRSTVWXZ")
	vowels := []byte("AEIOU")
	t := time.Now().UnixNano()
	nc := int64(len(consonants))
	nv := int64(len(vowels))
	code := []byte{
		consonants[t%nc],
		vowels[(t/nc)%nv],
		consonants[(t/(nc*nv))%nc],
		vowels[(t/(nc*nv*nc))%nv],
	}
	return string(code)
}
