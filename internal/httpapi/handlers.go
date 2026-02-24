package httpapi

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"ling/internal/service"
)

type Handler struct {
	svc *service.Service
}

func NewHandler(svc *service.Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) scan(w http.ResponseWriter, r *http.Request) {
	var req service.ScanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("scan decode error: %v", err)
		writeError(w, http.StatusBadRequest, "请求体格式不正确")
		return
	}

	resp, err := h.svc.Scan(req)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrUnsupportedObject), errors.Is(err, service.ErrScanInputRequired):
			log.Printf("scan bad request: child_id=%s label=%s err=%v", req.ChildID, req.DetectedLabel, err)
			writeError(w, http.StatusBadRequest, err.Error())
			return
		case errors.Is(err, service.ErrLLMUnavailable), errors.Is(err, service.ErrContentGenerate):
			log.Printf("scan unavailable: child_id=%s err=%v", req.ChildID, err)
			if errors.Is(err, service.ErrContentGenerate) {
				writeError(w, http.StatusServiceUnavailable, service.ErrContentGenerate.Error())
				return
			}
			writeError(w, http.StatusServiceUnavailable, err.Error())
			return
		default:
			log.Printf("scan internal error: child_id=%s label=%s err=%v", req.ChildID, req.DetectedLabel, err)
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
	}

	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) scanImage(w http.ResponseWriter, r *http.Request) {
	var req service.ScanImageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("scanImage decode error: %v", err)
		writeError(w, http.StatusBadRequest, "请求体格式不正确")
		return
	}

	resp, err := h.svc.ScanImage(req)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrImageRequired):
			log.Printf("scanImage bad request: child_id=%s err=%v", req.ChildID, err)
			writeError(w, http.StatusBadRequest, err.Error())
		case errors.Is(err, service.ErrLLMUnavailable):
			log.Printf("scanImage unavailable: child_id=%s err=%v", req.ChildID, err)
			writeError(w, http.StatusServiceUnavailable, err.Error())
		default:
			log.Printf("scanImage internal error: child_id=%s image_url=%t image_base64=%t err=%v", req.ChildID, strings.TrimSpace(req.ImageURL) != "", strings.TrimSpace(req.ImageBase64) != "", err)
			writeError(w, http.StatusInternalServerError, err.Error())
		}
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) answer(w http.ResponseWriter, r *http.Request) {
	var req service.AnswerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("answer decode error: %v", err)
		writeError(w, http.StatusBadRequest, "请求体格式不正确")
		return
	}

	resp, err := h.svc.SubmitAnswer(req)
	if err != nil {
		switch {
		case errors.Is(err, service.ErrSessionNotFound):
			log.Printf("answer not found: session_id=%s err=%v", req.SessionID, err)
			writeError(w, http.StatusNotFound, err.Error())
		case errors.Is(err, service.ErrAlreadyCaptured):
			log.Printf("answer conflict: session_id=%s err=%v", req.SessionID, err)
			writeError(w, http.StatusConflict, err.Error())
		default:
			log.Printf("answer internal error: session_id=%s err=%v", req.SessionID, err)
			writeError(w, http.StatusInternalServerError, err.Error())
		}
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

func (h *Handler) pokedex(w http.ResponseWriter, r *http.Request) {
	childID := strings.TrimSpace(r.URL.Query().Get("child_id"))
	entries, err := h.svc.Pokedex(childID)
	if err != nil {
		log.Printf("pokedex internal error: child_id=%s err=%v", childID, err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"child_id": childID,
		"entries":  entries,
	})
}

func (h *Handler) dailyReport(w http.ResponseWriter, r *http.Request) {
	childID := strings.TrimSpace(r.URL.Query().Get("child_id"))
	dateParam := strings.TrimSpace(r.URL.Query().Get("date"))
	day := time.Now()
	if dateParam != "" {
		parsed, err := time.Parse("2006-01-02", dateParam)
		if err != nil {
			log.Printf("dailyReport bad request: child_id=%s date=%s err=%v", childID, dateParam, err)
			writeError(w, http.StatusBadRequest, "date 必须是 YYYY-MM-DD 格式")
			return
		}
		day = parsed
	}

	report, err := h.svc.DailyReport(childID, day)
	if err != nil {
		log.Printf("dailyReport internal error: child_id=%s date=%s err=%v", childID, day.Format("2006-01-02"), err)
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, report)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{
		"error": message,
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
