package service_test

import (
	"encoding/base64"
	"encoding/json"
	"io"
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

func TestUnknownObjectFallsBackToTemplateContent(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	resp, err := svc.Scan(service.ScanRequest{
		ChildID:       "kid_2",
		ChildAge:      7,
		DetectedLabel: "spaceship",
	})
	if err != nil {
		t.Fatalf("Scan() error = %v", err)
	}
	if resp.SessionID == "" {
		t.Fatalf("expected session id")
	}
	if resp.Quiz == "" || resp.Fact == "" {
		t.Fatalf("expected fallback fact and quiz, got %+v", resp)
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

func TestGenerateCompanionSceneFallsBackWhenSceneLLMFailed(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	var mockImageURL string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/v1/chat/completions":
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte(`{"errorCode":500,"errMsg":"model invocation failed"}`))
		case r.Method == http.MethodPost && r.URL.Path == "/v1/byteplus/images/generations":
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("decode image payload failed: %v", err)
			}
			prompt, _ := payload["prompt"].(string)
			if !strings.Contains(prompt, "拟人化") {
				t.Fatalf("expected fallback prompt to include 拟人化, got %q", prompt)
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"data":[{"url":"` + mockImageURL + `"}]}`))
		case r.Method == http.MethodGet && r.URL.Path == "/mock-image.png":
			w.Header().Set("Content-Type", "image/png")
			_, _ = w.Write([]byte{1, 2, 3, 4})
		case r.Method == http.MethodPost && r.URL.Path == "/elevenlabs/tts/generate":
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write([]byte{5, 6, 7, 8})
		default:
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
	}))
	defer server.Close()
	mockImageURL = server.URL + "/mock-image.png"

	client, err := llm.NewClient(llm.Config{
		APIKey:       "test-key",
		BaseURL:      server.URL,
		ImageBaseURL: server.URL,
		VoiceBaseURL: server.URL,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	svc.SetLLMClient(client)

	resp, err := svc.GenerateCompanionScene(service.CompanionSceneRequest{
		ChildID:    "kid_fallback",
		ChildAge:   8,
		ObjectType: "猫",
		Weather:    "晴天",
	})
	if err != nil {
		t.Fatalf("GenerateCompanionScene() error = %v", err)
	}
	if strings.TrimSpace(resp.DialogText) == "" {
		t.Fatalf("expected dialog text from fallback scene")
	}
	if strings.TrimSpace(resp.CharacterImageURL) == "" {
		t.Fatalf("expected image url")
	}
	if len(resp.CharacterImageBase64) == 0 {
		t.Fatalf("expected image base64")
	}
	if len(resp.VoiceAudioBase64) == 0 {
		t.Fatalf("expected voice base64")
	}
	if _, err := base64.StdEncoding.DecodeString(resp.CharacterImageBase64); err != nil {
		t.Fatalf("invalid image base64: %v", err)
	}
	if _, err := base64.StdEncoding.DecodeString(resp.VoiceAudioBase64); err != nil {
		t.Fatalf("invalid voice base64: %v", err)
	}
}

func TestGenerateCompanionSceneImageToImageIgnoresEnvironmentFields(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	var mockImageURL string
	var chatRequestBody string
	var imagePrompt string
	var imageInput string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/v1/chat/completions":
			body, err := io.ReadAll(r.Body)
			if err != nil {
				t.Fatalf("read chat body failed: %v", err)
			}
			chatRequestBody = string(body)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"character_name\":\"喵喵星友\",\"personality\":\"温柔好奇\",\"dialog_text\":\"你好呀，我们一起观察吧！\",\"image_prompt\":\"旧的天气环境提示\"}"}}]}`))
		case r.Method == http.MethodPost && r.URL.Path == "/v1/byteplus/images/generations":
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("decode image payload failed: %v", err)
			}
			imagePrompt, _ = payload["prompt"].(string)
			imageInput, _ = payload["image"].(string)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"data":[{"url":"` + mockImageURL + `"}]}`))
		case r.Method == http.MethodGet && r.URL.Path == "/mock-image.png":
			w.Header().Set("Content-Type", "image/png")
			_, _ = w.Write([]byte{1, 2, 3})
		case r.Method == http.MethodPost && r.URL.Path == "/elevenlabs/tts/generate":
			w.Header().Set("Content-Type", "audio/mpeg")
			_, _ = w.Write([]byte{4, 5, 6})
		default:
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
	}))
	defer server.Close()
	mockImageURL = server.URL + "/mock-image.png"

	client, err := llm.NewClient(llm.Config{
		APIKey:       "test-key",
		BaseURL:      server.URL,
		ImageBaseURL: server.URL,
		VoiceBaseURL: server.URL,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	svc.SetLLMClient(client)

	resp, err := svc.GenerateCompanionScene(service.CompanionSceneRequest{
		ChildID:           "kid_i2i",
		ChildAge:          8,
		ObjectType:        "猫",
		Weather:           "暴雨夜晚",
		Environment:       "火山口",
		ObjectTraits:      "金属刺甲",
		SourceImageBase64: "Y2F0LWJhc2U2NA==",
	})
	if err != nil {
		t.Fatalf("GenerateCompanionScene() error = %v", err)
	}
	if strings.TrimSpace(resp.DialogText) == "" {
		t.Fatalf("expected dialog text")
	}
	if strings.Contains(chatRequestBody, "暴雨夜晚") || strings.Contains(chatRequestBody, "火山口") || strings.Contains(chatRequestBody, "金属刺甲") {
		t.Fatalf("expected scene request to ignore env fields in image-to-image mode, got %s", chatRequestBody)
	}
	if !strings.Contains(imagePrompt, "基于参考图进行图生图") {
		t.Fatalf("expected i2i prompt, got %q", imagePrompt)
	}
	if strings.Contains(imagePrompt, "旧的天气环境提示") {
		t.Fatalf("expected llm image prompt to be overridden in i2i mode, got %q", imagePrompt)
	}
	if imageInput != "data:image/jpeg;base64,Y2F0LWJhc2U2NA==" {
		t.Fatalf("expected normalized data url image input, got %q", imageInput)
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
