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
