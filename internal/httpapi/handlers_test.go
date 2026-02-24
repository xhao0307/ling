package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"ling/internal/knowledge"
	"ling/internal/service"
	"ling/internal/store"
)

func TestScanContentGenerateUnavailableReturns503WithoutInternalDetail(t *testing.T) {
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

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected status %d, got %d, body=%s", http.StatusServiceUnavailable, rec.Code, rec.Body.String())
	}

	var resp map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response error = %v", err)
	}
	if got := resp["error"]; got != service.ErrContentGenerate.Error() {
		t.Fatalf("expected error %q, got %q", service.ErrContentGenerate.Error(), got)
	}
	if strings.Contains(rec.Body.String(), "object_type=") || strings.Contains(rec.Body.String(), "llm_error=") {
		t.Fatalf("response should not leak internal detail, got %s", rec.Body.String())
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
