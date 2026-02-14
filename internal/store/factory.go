package store

import (
	"errors"
	"strings"
)

const (
	EngineJSON   = "json"
	EngineSQLite = "sqlite"
)

func NewByEngine(engine string, path string) (Store, error) {
	switch strings.ToLower(strings.TrimSpace(engine)) {
	case "", EngineSQLite:
		return NewSQLiteStore(path)
	case EngineJSON:
		return NewJSONStore(path)
	default:
		return nil, errors.New("unsupported store engine: " + engine)
	}
}
