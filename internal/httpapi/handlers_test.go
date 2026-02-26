package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"ling/internal/knowledge"
	"ling/internal/llm"
	"ling/internal/service"
	"ling/internal/store"
)

func TestScanUnknownObjectFallsBackTo200(t *testing.T) {
	st, err := store.NewJSONStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	svc := service.New(st, knowledge.BaseKnowledge)
	h := NewHandler(svc)

	body := map[string]any{
		"child_id":       "kid_httpapi_1",
		"child_age":      8,
		"detected_label": "spaceship",
	}
	payload, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/scan", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	h.scan(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d, body=%s", http.StatusOK, rec.Code, rec.Body.String())
	}

	var resp map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response error = %v", err)
	}
	sessionID, _ := resp["session_id"].(string)
	if got := strings.TrimSpace(sessionID); got == "" {
		t.Fatalf("expected session_id in response, got %v", resp)
	}
}

func TestCompanionSceneUnavailableReturns503(t *testing.T) {
	st, err := store.NewJSONStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	svc := service.New(st, knowledge.BaseKnowledge)
	h := NewHandler(svc)

	body := map[string]any{
		"child_id":    "kid_httpapi_2",
		"child_age":   8,
		"object_type": "路灯",
		"weather":     "晴天",
	}
	payload, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/companion/scene", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	h.companionScene(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected status %d, got %d, body=%s", http.StatusServiceUnavailable, rec.Code, rec.Body.String())
	}

	var resp map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response error = %v", err)
	}
	if got := resp["error"]; got != service.ErrLLMUnavailable.Error() {
		t.Fatalf("expected error %q, got %q", service.ErrLLMUnavailable.Error(), got)
	}
}

func TestCompanionSceneMissingObjectTypeReturns400(t *testing.T) {
	st, err := store.NewJSONStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	svc := service.New(st, knowledge.BaseKnowledge)
	h := NewHandler(svc)

	body := map[string]any{
		"child_id":  "kid_httpapi_3",
		"child_age": 8,
	}
	payload, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/companion/scene", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	h.companionScene(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d, body=%s", http.StatusBadRequest, rec.Code, rec.Body.String())
	}
}

func TestCompanionChatUnavailableReturns503(t *testing.T) {
	st, err := store.NewJSONStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	svc := service.New(st, knowledge.BaseKnowledge)
	h := NewHandler(svc)

	body := map[string]any{
		"child_id":      "kid_httpapi_4",
		"child_age":     8,
		"object_type":   "路灯",
		"child_message": "你好",
	}
	payload, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/companion/chat", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	h.companionChat(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected status %d, got %d, body=%s", http.StatusServiceUnavailable, rec.Code, rec.Body.String())
	}
}

func TestCompanionChatMissingMessageReturns400(t *testing.T) {
	st, err := store.NewJSONStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	svc := service.New(st, knowledge.BaseKnowledge)
	h := NewHandler(svc)

	body := map[string]any{
		"child_id":    "kid_httpapi_5",
		"child_age":   8,
		"object_type": "路灯",
	}
	payload, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/companion/chat", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	h.companionChat(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d, body=%s", http.StatusBadRequest, rec.Code, rec.Body.String())
	}
}

func TestCompanionChatTimeoutReturns504(t *testing.T) {
	st, err := store.NewJSONStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	svc := service.New(st, knowledge.BaseKnowledge)
	h := NewHandler(svc)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/compatible-mode/v1/chat/completions" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		time.Sleep(80 * time.Millisecond)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"reply_text\":\"你好\"}"}}]}`))
	}))
	defer server.Close()

	client, err := llm.NewClient(llm.Config{
		APIKey:               "test-key",
		BaseURL:              server.URL,
		Timeout:              20 * time.Millisecond,
		CompanionChatTimeout: 20 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	svc.SetLLMClient(client)

	body := map[string]any{
		"child_id":      "kid_httpapi_timeout",
		"child_age":     8,
		"object_type":   "猫",
		"child_message": "为什么会这样？",
	}
	payload, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/companion/chat", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	h.companionChat(rec, req)

	if rec.Code != http.StatusGatewayTimeout {
		t.Fatalf("expected status %d, got %d, body=%s", http.StatusGatewayTimeout, rec.Code, rec.Body.String())
	}
}

func TestCompanionVoiceUnavailableReturns503(t *testing.T) {
	st, err := store.NewJSONStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	svc := service.New(st, knowledge.BaseKnowledge)
	h := NewHandler(svc)

	body := map[string]any{
		"child_id":    "kid_httpapi_6",
		"child_age":   8,
		"object_type": "路灯",
		"text":        "你好",
	}
	payload, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/companion/voice", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	h.companionVoice(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected status %d, got %d, body=%s", http.StatusServiceUnavailable, rec.Code, rec.Body.String())
	}
}

func TestCompanionVoiceMissingTextReturns400(t *testing.T) {
	st, err := store.NewJSONStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	svc := service.New(st, knowledge.BaseKnowledge)
	h := NewHandler(svc)

	body := map[string]any{
		"child_id":    "kid_httpapi_7",
		"child_age":   8,
		"object_type": "路灯",
	}
	payload, _ := json.Marshal(body)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/companion/voice", bytes.NewReader(payload))
	rec := httptest.NewRecorder()
	h.companionVoice(rec, req)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d, body=%s", http.StatusBadRequest, rec.Code, rec.Body.String())
	}
}
