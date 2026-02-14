package store

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"time"

	"ling/internal/model"
)

type fileState struct {
	Spirits  map[string]model.Spirit      `json:"spirits"`
	Sessions map[string]model.ScanSession `json:"sessions"`
	Captures []model.Capture              `json:"captures"`
}

type JSONStore struct {
	filePath string
	mu       sync.RWMutex
	state    fileState
}

func NewJSONStore(filePath string) (*JSONStore, error) {
	s := &JSONStore{
		filePath: filePath,
		state: fileState{
			Spirits:  make(map[string]model.Spirit),
			Sessions: make(map[string]model.ScanSession),
			Captures: make([]model.Capture, 0),
		},
	}
	if err := s.load(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *JSONStore) SaveSpirit(spirit model.Spirit) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Spirits[spirit.ID] = spirit
	return s.persistLocked()
}

func (s *JSONStore) GetSpirit(id string) (model.Spirit, bool, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	spirit, ok := s.state.Spirits[id]
	return spirit, ok, nil
}

func (s *JSONStore) SaveSession(session model.ScanSession) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Sessions[session.ID] = session
	return s.persistLocked()
}

func (s *JSONStore) GetSession(id string) (model.ScanSession, bool, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	session, ok := s.state.Sessions[id]
	return session, ok, nil
}

func (s *JSONStore) UpdateSession(session model.ScanSession) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.state.Sessions[session.ID]; !ok {
		return errors.New("session not found")
	}
	s.state.Sessions[session.ID] = session
	return s.persistLocked()
}

func (s *JSONStore) AddCapture(capture model.Capture) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.state.Captures = append(s.state.Captures, capture)
	return s.persistLocked()
}

func (s *JSONStore) ListCapturesByChild(childID string) ([]model.Capture, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]model.Capture, 0)
	for _, capture := range s.state.Captures {
		if capture.ChildID == childID {
			result = append(result, capture)
		}
	}
	return result, nil
}

func (s *JSONStore) ListCapturesByChildAndDate(childID string, day time.Time) ([]model.Capture, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	year, month, date := day.Date()
	result := make([]model.Capture, 0)
	for _, capture := range s.state.Captures {
		cy, cm, cd := capture.CapturedAt.Date()
		if capture.ChildID == childID && cy == year && cm == month && cd == date {
			result = append(result, capture)
		}
	}
	return result, nil
}

func (s *JSONStore) load() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	data, err := os.ReadFile(s.filePath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	var state fileState
	if err := json.Unmarshal(data, &state); err != nil {
		return err
	}
	if state.Spirits == nil {
		state.Spirits = make(map[string]model.Spirit)
	}
	if state.Sessions == nil {
		state.Sessions = make(map[string]model.ScanSession)
	}
	if state.Captures == nil {
		state.Captures = make([]model.Capture, 0)
	}
	s.state = state
	return nil
}

func (s *JSONStore) persistLocked() error {
	if err := os.MkdirAll(filepath.Dir(s.filePath), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(s.state, "", "  ")
	if err != nil {
		return err
	}

	tmpPath := s.filePath + ".tmp"
	if err := os.WriteFile(tmpPath, data, 0o644); err != nil {
		return err
	}
	return os.Rename(tmpPath, s.filePath)
}
