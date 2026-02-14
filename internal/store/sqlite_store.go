package store

import (
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"

	"ling/internal/model"
)

type SQLiteStore struct {
	db *sql.DB
}

func NewSQLiteStore(filePath string) (*SQLiteStore, error) {
	if err := os.MkdirAll(filepath.Dir(filePath), 0o755); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", filePath)
	if err != nil {
		return nil, err
	}
	st := &SQLiteStore{db: db}
	if err := st.initSchema(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return st, nil
}

func (s *SQLiteStore) Close() error {
	return s.db.Close()
}

func (s *SQLiteStore) SaveSpirit(spirit model.Spirit) error {
	_, err := s.db.Exec(`
		INSERT OR REPLACE INTO spirits
		(id, name, object_type, personality, intro, created_at)
		VALUES (?, ?, ?, ?, ?, ?)`,
		spirit.ID,
		spirit.Name,
		spirit.ObjectType,
		spirit.Personality,
		spirit.Intro,
		toTS(spirit.CreatedAt),
	)
	return err
}

func (s *SQLiteStore) GetSpirit(id string) (model.Spirit, bool, error) {
	row := s.db.QueryRow(`
		SELECT id, name, object_type, personality, intro, created_at
		FROM spirits
		WHERE id = ?`,
		id,
	)
	var spirit model.Spirit
	var createdAt string
	err := row.Scan(
		&spirit.ID,
		&spirit.Name,
		&spirit.ObjectType,
		&spirit.Personality,
		&spirit.Intro,
		&createdAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return model.Spirit{}, false, nil
	}
	if err != nil {
		return model.Spirit{}, false, err
	}
	spirit.CreatedAt = fromTS(createdAt)
	return spirit, true, nil
}

func (s *SQLiteStore) SaveSession(session model.ScanSession) error {
	_, err := s.db.Exec(`
		INSERT INTO sessions
		(id, child_id, child_age, object_type, spirit_id, quiz_q, quiz_a, fact, created_at, cache_hit, captured, captured_at, answer_given)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		session.ID,
		session.ChildID,
		session.ChildAge,
		session.ObjectType,
		session.SpiritID,
		session.QuizQ,
		session.QuizA,
		session.Fact,
		toTS(session.CreatedAt),
		boolToInt(session.CacheHit),
		boolToInt(session.Captured),
		nullableTS(session.CapturedAt),
		session.AnswerGiven,
	)
	return err
}

func (s *SQLiteStore) GetSession(id string) (model.ScanSession, bool, error) {
	row := s.db.QueryRow(`
		SELECT id, child_id, child_age, object_type, spirit_id, quiz_q, quiz_a, fact, created_at, cache_hit, captured, captured_at, answer_given
		FROM sessions
		WHERE id = ?`,
		id,
	)

	var session model.ScanSession
	var createdAt string
	var cacheHit int
	var captured int
	var capturedAt sql.NullString
	err := row.Scan(
		&session.ID,
		&session.ChildID,
		&session.ChildAge,
		&session.ObjectType,
		&session.SpiritID,
		&session.QuizQ,
		&session.QuizA,
		&session.Fact,
		&createdAt,
		&cacheHit,
		&captured,
		&capturedAt,
		&session.AnswerGiven,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return model.ScanSession{}, false, nil
	}
	if err != nil {
		return model.ScanSession{}, false, err
	}

	session.CreatedAt = fromTS(createdAt)
	session.CacheHit = intToBool(cacheHit)
	session.Captured = intToBool(captured)
	if capturedAt.Valid && capturedAt.String != "" {
		session.CapturedAt = fromTS(capturedAt.String)
	}

	return session, true, nil
}

func (s *SQLiteStore) UpdateSession(session model.ScanSession) error {
	result, err := s.db.Exec(`
		UPDATE sessions
		SET child_id = ?, child_age = ?, object_type = ?, spirit_id = ?, quiz_q = ?, quiz_a = ?, fact = ?, created_at = ?, cache_hit = ?, captured = ?, captured_at = ?, answer_given = ?
		WHERE id = ?`,
		session.ChildID,
		session.ChildAge,
		session.ObjectType,
		session.SpiritID,
		session.QuizQ,
		session.QuizA,
		session.Fact,
		toTS(session.CreatedAt),
		boolToInt(session.CacheHit),
		boolToInt(session.Captured),
		nullableTS(session.CapturedAt),
		session.AnswerGiven,
		session.ID,
	)
	if err != nil {
		return err
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return errors.New("session not found")
	}
	return nil
}

func (s *SQLiteStore) AddCapture(capture model.Capture) error {
	_, err := s.db.Exec(`
		INSERT INTO captures
		(id, child_id, spirit_id, spirit_name, object_type, fact, captured_at)
		VALUES (?, ?, ?, ?, ?, ?, ?)`,
		capture.ID,
		capture.ChildID,
		capture.SpiritID,
		capture.SpiritName,
		capture.ObjectType,
		capture.Fact,
		toTS(capture.CapturedAt),
	)
	return err
}

func (s *SQLiteStore) ListCapturesByChild(childID string) ([]model.Capture, error) {
	rows, err := s.db.Query(`
		SELECT id, child_id, spirit_id, spirit_name, object_type, fact, captured_at
		FROM captures
		WHERE child_id = ?
		ORDER BY captured_at DESC`,
		childID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []model.Capture
	for rows.Next() {
		var capture model.Capture
		var capturedAt string
		if err := rows.Scan(
			&capture.ID,
			&capture.ChildID,
			&capture.SpiritID,
			&capture.SpiritName,
			&capture.ObjectType,
			&capture.Fact,
			&capturedAt,
		); err != nil {
			return nil, err
		}
		capture.CapturedAt = fromTS(capturedAt)
		result = append(result, capture)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

func (s *SQLiteStore) ListCapturesByChildAndDate(childID string, day time.Time) ([]model.Capture, error) {
	start := day.In(time.Local).Truncate(24 * time.Hour)
	end := start.Add(24 * time.Hour)

	rows, err := s.db.Query(`
		SELECT id, child_id, spirit_id, spirit_name, object_type, fact, captured_at
		FROM captures
		WHERE child_id = ? AND captured_at >= ? AND captured_at < ?
		ORDER BY captured_at DESC`,
		childID,
		toTS(start),
		toTS(end),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var result []model.Capture
	for rows.Next() {
		var capture model.Capture
		var capturedAt string
		if err := rows.Scan(
			&capture.ID,
			&capture.ChildID,
			&capture.SpiritID,
			&capture.SpiritName,
			&capture.ObjectType,
			&capture.Fact,
			&capturedAt,
		); err != nil {
			return nil, err
		}
		capture.CapturedAt = fromTS(capturedAt)
		result = append(result, capture)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

func (s *SQLiteStore) initSchema() error {
	_, err := s.db.Exec(`
		PRAGMA journal_mode=WAL;
		CREATE TABLE IF NOT EXISTS spirits (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			object_type TEXT NOT NULL,
			personality TEXT NOT NULL,
			intro TEXT NOT NULL,
			created_at TEXT NOT NULL
		);
		CREATE TABLE IF NOT EXISTS sessions (
			id TEXT PRIMARY KEY,
			child_id TEXT NOT NULL,
			child_age INTEGER NOT NULL,
			object_type TEXT NOT NULL,
			spirit_id TEXT NOT NULL,
			quiz_q TEXT NOT NULL,
			quiz_a TEXT NOT NULL,
			fact TEXT NOT NULL,
			created_at TEXT NOT NULL,
			cache_hit INTEGER NOT NULL,
			captured INTEGER NOT NULL,
			captured_at TEXT,
			answer_given TEXT NOT NULL DEFAULT ''
		);
		CREATE TABLE IF NOT EXISTS captures (
			id TEXT PRIMARY KEY,
			child_id TEXT NOT NULL,
			spirit_id TEXT NOT NULL,
			spirit_name TEXT NOT NULL,
			object_type TEXT NOT NULL,
			fact TEXT NOT NULL,
			captured_at TEXT NOT NULL
		);
		CREATE INDEX IF NOT EXISTS idx_captures_child_time ON captures(child_id, captured_at);
	`)
	return err
}

func toTS(t time.Time) string {
	return t.UTC().Format(time.RFC3339Nano)
}

func nullableTS(t time.Time) any {
	if t.IsZero() {
		return nil
	}
	return toTS(t)
}

func fromTS(v string) time.Time {
	t, err := time.Parse(time.RFC3339Nano, v)
	if err != nil {
		return time.Time{}
	}
	return t
}

func boolToInt(v bool) int {
	if v {
		return 1
	}
	return 0
}

func intToBool(v int) bool {
	return v != 0
}
