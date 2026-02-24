package service_test

import (
	"path/filepath"
	"testing"
	"time"

	"ling/internal/knowledge"
	"ling/internal/service"
	"ling/internal/store"
)

func TestScanAndCaptureFlow(t *testing.T) {
	t.Parallel()

	svc, st := newTestService(t)

	scanResp, err := svc.Scan(service.ScanRequest{
		ChildID:       "kid_1",
		ChildAge:      8,
		DetectedLabel: "mailbox",
	})
	if err != nil {
		t.Fatalf("Scan() error = %v", err)
	}
	if scanResp.SessionID == "" {
		t.Fatalf("expected session id")
	}
	if scanResp.Spirit.ID == "" {
		t.Fatalf("expected spirit id")
	}
	if len(scanResp.Dialogues) == 0 {
		t.Fatalf("expected generated dialogues")
	}

	session, ok, err := st.GetSession(scanResp.SessionID)
	if err != nil {
		t.Fatalf("GetSession() error = %v", err)
	}
	if !ok {
		t.Fatalf("expected session to be stored")
	}

	answerResp, err := svc.SubmitAnswer(service.AnswerRequest{
		SessionID: scanResp.SessionID,
		ChildID:   "kid_1",
		Answer:    session.QuizA,
	})
	if err != nil {
		t.Fatalf("SubmitAnswer() error = %v", err)
	}
	if !answerResp.Correct || !answerResp.Captured {
		t.Fatalf("expected capture success, got %+v", answerResp)
	}

	pokedex, err := svc.Pokedex("kid_1")
	if err != nil {
		t.Fatalf("Pokedex() error = %v", err)
	}
	if len(pokedex) != 1 {
		t.Fatalf("expected 1 pokedex entry, got %d", len(pokedex))
	}
}

func TestUnsupportedObject(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	_, err := svc.Scan(service.ScanRequest{
		ChildID:       "kid_2",
		ChildAge:      7,
		DetectedLabel: "spaceship",
	})
	if err == nil {
		t.Fatalf("expected error for unsupported object")
	}
}

func TestDailyReport(t *testing.T) {
	t.Parallel()
	svc, st := newTestService(t)

	scanResp, err := svc.Scan(service.ScanRequest{
		ChildID:       "kid_3",
		ChildAge:      6,
		DetectedLabel: "tree",
	})
	if err != nil {
		t.Fatalf("Scan() error = %v", err)
	}
	session, ok, err := st.GetSession(scanResp.SessionID)
	if err != nil || !ok {
		t.Fatalf("GetSession() error = %v, ok=%v", err, ok)
	}
	if _, err := svc.SubmitAnswer(service.AnswerRequest{
		SessionID: scanResp.SessionID,
		ChildID:   "kid_3",
		Answer:    session.QuizA,
	}); err != nil {
		t.Fatalf("SubmitAnswer() error = %v", err)
	}

	report, err := svc.DailyReport("kid_3", time.Now())
	if err != nil {
		t.Fatalf("DailyReport() error = %v", err)
	}
	if report.TotalCaptured != 1 {
		t.Fatalf("expected total captured = 1, got %d", report.TotalCaptured)
	}
	if len(report.KnowledgePoints) == 0 {
		t.Fatalf("expected at least one knowledge point")
	}
}

func TestGenerateCompanionSceneRequiresLLM(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	_, err := svc.GenerateCompanionScene(service.CompanionSceneRequest{
		ChildID:    "kid_4",
		ChildAge:   8,
		ObjectType: "路灯",
	})
	if err == nil {
		t.Fatalf("expected error")
	}
	if err != service.ErrLLMUnavailable {
		t.Fatalf("expected ErrLLMUnavailable, got %v", err)
	}
}

func TestGenerateCompanionSceneMissingObjectType(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	_, err := svc.GenerateCompanionScene(service.CompanionSceneRequest{
		ChildID:  "kid_5",
		ChildAge: 8,
	})
	if err == nil {
		t.Fatalf("expected error")
	}
	if err != service.ErrObjectTypeMissing {
		t.Fatalf("expected ErrObjectTypeMissing, got %v", err)
	}
}

func TestGenerateCompanionSceneInvalidAge(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	_, err := svc.GenerateCompanionScene(service.CompanionSceneRequest{
		ChildID:    "kid_6",
		ChildAge:   2,
		ObjectType: "路灯",
	})
	if err == nil {
		t.Fatalf("expected error")
	}
	if err != service.ErrInvalidChildAge {
		t.Fatalf("expected ErrInvalidChildAge, got %v", err)
	}
}

func TestChatCompanionRequiresLLM(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	_, err := svc.ChatCompanion(service.CompanionChatRequest{
		ChildID:      "kid_7",
		ChildAge:     8,
		ObjectType:   "路灯",
		ChildMessage: "你好",
	})
	if err == nil {
		t.Fatalf("expected error")
	}
	if err != service.ErrLLMUnavailable {
		t.Fatalf("expected ErrLLMUnavailable, got %v", err)
	}
}

func TestChatCompanionMissingMessage(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	_, err := svc.ChatCompanion(service.CompanionChatRequest{
		ChildID:    "kid_8",
		ChildAge:   8,
		ObjectType: "路灯",
	})
	if err == nil {
		t.Fatalf("expected error")
	}
	if err != service.ErrChildMessageEmpty {
		t.Fatalf("expected ErrChildMessageEmpty, got %v", err)
	}
}

func newTestService(t *testing.T) (*service.Service, *store.JSONStore) {
	t.Helper()
	dataFile := filepath.Join(t.TempDir(), "state.json")
	st, err := store.NewJSONStore(dataFile)
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	return service.New(st, knowledge.BaseKnowledge), st
}
