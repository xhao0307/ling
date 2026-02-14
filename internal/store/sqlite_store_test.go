package store_test

import (
	"path/filepath"
	"testing"
	"time"

	"ling/internal/model"
	"ling/internal/store"
)

func TestSQLiteStoreBasicFlow(t *testing.T) {
	t.Parallel()

	dbPath := filepath.Join(t.TempDir(), "cityling.db")
	st, err := store.NewSQLiteStore(dbPath)
	if err != nil {
		t.Fatalf("NewSQLiteStore() error = %v", err)
	}
	t.Cleanup(func() {
		_ = st.Close()
	})

	now := time.Now().UTC()

	spirit := model.Spirit{
		ID:          "spirit_1",
		Name:        "Leafin",
		ObjectType:  "tree",
		Personality: "friendly",
		Intro:       "intro",
		CreatedAt:   now,
	}
	if err := st.SaveSpirit(spirit); err != nil {
		t.Fatalf("SaveSpirit() error = %v", err)
	}
	gotSpirit, ok, err := st.GetSpirit(spirit.ID)
	if err != nil || !ok {
		t.Fatalf("GetSpirit() err=%v ok=%v", err, ok)
	}
	if gotSpirit.Name != spirit.Name {
		t.Fatalf("expected spirit name %q got %q", spirit.Name, gotSpirit.Name)
	}

	session := model.ScanSession{
		ID:         "sess_1",
		ChildID:    "kid",
		ChildAge:   8,
		ObjectType: "tree",
		SpiritID:   spirit.ID,
		QuizQ:      "Q",
		QuizA:      "A",
		Fact:       "F",
		CreatedAt:  now,
		CacheHit:   false,
	}
	if err := st.SaveSession(session); err != nil {
		t.Fatalf("SaveSession() error = %v", err)
	}

	gotSession, ok, err := st.GetSession(session.ID)
	if err != nil || !ok {
		t.Fatalf("GetSession() err=%v ok=%v", err, ok)
	}
	gotSession.Captured = true
	gotSession.CapturedAt = now.Add(30 * time.Second)
	gotSession.AnswerGiven = "A"
	if err := st.UpdateSession(gotSession); err != nil {
		t.Fatalf("UpdateSession() error = %v", err)
	}

	capture := model.Capture{
		ID:         "cap_1",
		ChildID:    "kid",
		SpiritID:   spirit.ID,
		SpiritName: spirit.Name,
		ObjectType: "tree",
		Fact:       "F",
		CapturedAt: now.Add(1 * time.Minute),
	}
	if err := st.AddCapture(capture); err != nil {
		t.Fatalf("AddCapture() error = %v", err)
	}

	list, err := st.ListCapturesByChild("kid")
	if err != nil {
		t.Fatalf("ListCapturesByChild() error = %v", err)
	}
	if len(list) != 1 {
		t.Fatalf("expected 1 capture, got %d", len(list))
	}

	dayList, err := st.ListCapturesByChildAndDate("kid", now)
	if err != nil {
		t.Fatalf("ListCapturesByChildAndDate() error = %v", err)
	}
	if len(dayList) != 1 {
		t.Fatalf("expected 1 day capture, got %d", len(dayList))
	}
}
