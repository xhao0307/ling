package httpapi

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"ling/internal/knowledge"
	"ling/internal/service"
	"ling/internal/store"
)

func TestWithCORSPreflight(t *testing.T) {
	h := withCORS(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t.Fatalf("preflight request should not reach next handler")
	}))

	req := httptest.NewRequest(http.MethodOptions, "/api/v1/scan/image", nil)
	req.Header.Set("Origin", "http://127.0.0.1:7357")
	req.Header.Set("Access-Control-Request-Method", http.MethodPost)
	req.Header.Set("Access-Control-Request-Headers", "content-type")
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusNoContent {
		t.Fatalf("expected status %d, got %d", http.StatusNoContent, rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("expected Access-Control-Allow-Origin '*', got %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); got == "" {
		t.Fatalf("expected Access-Control-Allow-Methods to be set")
	}
	if got := rec.Header().Get("Access-Control-Allow-Headers"); got == "" {
		t.Fatalf("expected Access-Control-Allow-Headers to be set")
	}
}

func TestWithCORSAddsHeadersForNormalRequest(t *testing.T) {
	h := withCORS(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
	rec := httptest.NewRecorder()

	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("expected Access-Control-Allow-Origin '*', got %q", got)
	}
}

func TestCompanionSceneRouteRegistered(t *testing.T) {
	st, err := store.NewJSONStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatalf("NewJSONStore() error = %v", err)
	}
	svc := service.New(st, knowledge.BaseKnowledge)
	router := NewRouter(NewHandler(svc))

	body := []byte(`{"child_id":"kid","child_age":8,"object_type":"路灯"}`)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/companion/scene", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)

	if rec.Code == http.StatusNotFound {
		t.Fatalf("expected companion scene route to be registered, got 404")
	}
}
