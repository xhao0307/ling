package httpapi

import (
	"log"
	"net/http"
	"time"
)

func NewRouter(handler *Handler) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", handler.healthz)
	mux.HandleFunc("GET /docs", handler.swaggerUI)
	mux.HandleFunc("GET /docs/", handler.swaggerUI)
	mux.HandleFunc("GET /docs/openapi.json", handler.swaggerSpec)
	mux.HandleFunc("GET /swagger", handler.swaggerUI)
	mux.HandleFunc("GET /swagger/", handler.swaggerUI)
	mux.HandleFunc("GET /swagger/openapi.json", handler.swaggerSpec)
	mux.HandleFunc("POST /api/v1/scan", handler.scan)
	mux.HandleFunc("POST /api/v1/scan/image", handler.scanImage)
	mux.HandleFunc("POST /api/v1/answer", handler.answer)
	mux.HandleFunc("GET /api/v1/pokedex", handler.pokedex)
	mux.HandleFunc("GET /api/v1/report/daily", handler.dailyReport)

	return withRequestLogging(withCORS(withJSONContentType(mux)))
}

func withJSONContentType(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodPost && r.Header.Get("Content-Type") == "" {
			r.Header.Set("Content-Type", "application/json")
		}
		next.ServeHTTP(w, r)
	})
}

func withRequestLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Printf("%s %s -> %d (%s) from %s", r.Method, r.URL.RequestURI(), rec.status, time.Since(start).Truncate(time.Millisecond), r.RemoteAddr)
	})
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Max-Age", "600")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(statusCode int) {
	r.status = statusCode
	r.ResponseWriter.WriteHeader(statusCode)
}
