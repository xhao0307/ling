package store

import (
	"time"

	"ling/internal/model"
)

type Store interface {
	SaveSpirit(spirit model.Spirit) error
	GetSpirit(id string) (model.Spirit, bool, error)

	SaveSession(session model.ScanSession) error
	GetSession(id string) (model.ScanSession, bool, error)
	UpdateSession(session model.ScanSession) error

	AddCapture(capture model.Capture) error
	ListCapturesByChild(childID string) ([]model.Capture, error)
	ListCapturesByChildAndDate(childID string, day time.Time) ([]model.Capture, error)
}
