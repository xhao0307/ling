package service_test

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"ling/internal/knowledge"
	"ling/internal/llm"
	"ling/internal/model"
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

func TestSubmitAnswerOutsideBadgeScopeDoesNotCapturePokedex(t *testing.T) {
	t.Parallel()
	svc, st := newTestService(t)

	scanResp, err := svc.Scan(service.ScanRequest{
		ChildID:       "kid_outside",
		ChildAge:      8,
		DetectedLabel: "spaceship_console",
	})
	if err != nil {
		t.Fatalf("Scan() error = %v", err)
	}
	session, ok, err := st.GetSession(scanResp.SessionID)
	if err != nil || !ok {
		t.Fatalf("GetSession() error = %v, ok=%v", err, ok)
	}

	answerResp, err := svc.SubmitAnswer(service.AnswerRequest{
		SessionID: scanResp.SessionID,
		ChildID:   "kid_outside",
		Answer:    session.QuizA,
	})
	if err != nil {
		t.Fatalf("SubmitAnswer() error = %v", err)
	}
	if !answerResp.Correct {
		t.Fatalf("expected correct answer")
	}
	if answerResp.Captured {
		t.Fatalf("expected non-badge object not to be captured in pokedex")
	}

	pokedex, err := svc.Pokedex("kid_outside")
	if err != nil {
		t.Fatalf("Pokedex() error = %v", err)
	}
	if len(pokedex) != 0 {
		t.Fatalf("expected no pokedex captures for non-badge object, got %d", len(pokedex))
	}
}

func TestPokedexBadgesRequireFullCollectionToUnlock(t *testing.T) {
	t.Parallel()
	svc, st := newTestService(t)

	scanResp, err := svc.Scan(service.ScanRequest{
		ChildID:       "kid_badge",
		ChildAge:      8,
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
		ChildID:   "kid_badge",
		Answer:    session.QuizA,
	}); err != nil {
		t.Fatalf("SubmitAnswer() error = %v", err)
	}

	badges, err := svc.PokedexBadges("kid_badge")
	if err != nil {
		t.Fatalf("PokedexBadges() error = %v", err)
	}
	var plantBadge *model.PokedexBadge
	for i := range badges {
		if badges[i].Code == "PLANTAE" {
			plantBadge = &badges[i]
			break
		}
	}
	if plantBadge == nil {
		t.Fatalf("expected PLANTAE badge")
	}
	if plantBadge.Progress < 1 {
		t.Fatalf("expected progress >= 1, got %d", plantBadge.Progress)
	}
	if plantBadge.Target <= 1 {
		t.Fatalf("expected full-collection target > 1, got %d", plantBadge.Target)
	}
	if plantBadge.Unlocked {
		t.Fatalf("expected badge to remain locked before full collection")
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
	var mockAudioURL string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/compatible-mode/v1/chat/completions":
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
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/services/aigc/multimodal-generation/generation":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"status_code":200,"request_id":"req-voice-1","output":{"audio":{"url":"` + mockAudioURL + `"}}}`))
		case r.Method == http.MethodGet && r.URL.Path == "/mock-audio.wav":
			w.Header().Set("Content-Type", "audio/wav")
			_, _ = w.Write([]byte{5, 6, 7, 8})
		default:
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
	}))
	defer server.Close()
	mockImageURL = server.URL + "/mock-image.png"
	mockAudioURL = server.URL + "/mock-audio.wav"

	client, err := llm.NewClient(llm.Config{
		APIKey:              "test-key",
		BaseURL:             server.URL,
		ImageBaseURL:        server.URL,
		ImageResponseFormat: "b64_json",
		VoiceBaseURL:        server.URL,
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
	if !strings.Contains(resp.DialogText, "我现在正开心") {
		t.Fatalf("expected dialog first line to include emotion+state hook, got %q", resp.DialogText)
	}
	if !strings.Contains(resp.DialogText, "我是猫") {
		t.Fatalf("expected fallback scene to use object identity, got %q", resp.DialogText)
	}
	if strings.Contains(resp.DialogText, "我是小冒险家") {
		t.Fatalf("expected fallback scene not to use detached role, got %q", resp.DialogText)
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
	var mockAudioURL string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/compatible-mode/v1/chat/completions":
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
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/services/aigc/multimodal-generation/generation":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"status_code":200,"request_id":"req-voice-2","output":{"audio":{"url":"` + mockAudioURL + `"}}}`))
		case r.Method == http.MethodGet && r.URL.Path == "/mock-audio.wav":
			w.Header().Set("Content-Type", "audio/wav")
			_, _ = w.Write([]byte{4, 5, 6})
		default:
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
	}))
	defer server.Close()
	mockImageURL = server.URL + "/mock-image.png"
	mockAudioURL = server.URL + "/mock-audio.wav"

	client, err := llm.NewClient(llm.Config{
		APIKey:              "test-key",
		BaseURL:             server.URL,
		ImageBaseURL:        server.URL,
		ImageResponseFormat: "b64_json",
		VoiceBaseURL:        server.URL,
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
	if !strings.Contains(resp.DialogText, "我是猫") || !strings.Contains(resp.DialogText, "我现在正开心") {
		t.Fatalf("expected dialog first line to include identity+emotion hook, got %q", resp.DialogText)
	}
	if strings.Contains(resp.DialogText, "我是小冒险家") {
		t.Fatalf("expected object-centered identity, got %q", resp.DialogText)
	}
	if strings.Contains(chatRequestBody, "暴雨夜晚") || strings.Contains(chatRequestBody, "火山口") || strings.Contains(chatRequestBody, "金属刺甲") {
		t.Fatalf("expected scene request to ignore env fields in image-to-image mode, got %s", chatRequestBody)
	}
	if !strings.Contains(imagePrompt, "基于参考图进行图生图") {
		t.Fatalf("expected i2i prompt, got %q", imagePrompt)
	}
	if !strings.Contains(imagePrompt, "日常生活场景背景") {
		t.Fatalf("expected i2i prompt to add daily scene background, got %q", imagePrompt)
	}
	if !strings.Contains(imagePrompt, "可视面积约占1/5") {
		t.Fatalf("expected i2i prompt to constrain subject size, got %q", imagePrompt)
	}
	if !strings.Contains(imagePrompt, "看向镜头") {
		t.Fatalf("expected i2i prompt to require looking at screen, got %q", imagePrompt)
	}
	if !strings.Contains(imagePrompt, "位置居中或微偏中景") {
		t.Fatalf("expected i2i prompt to constrain centered composition, got %q", imagePrompt)
	}
	if !strings.Contains(imagePrompt, "现实生活中的常见出现环境") {
		t.Fatalf("expected i2i prompt to require realistic scene, got %q", imagePrompt)
	}
	if strings.Contains(imagePrompt, "旧的天气环境提示") {
		t.Fatalf("expected llm image prompt to be overridden in i2i mode, got %q", imagePrompt)
	}
	if imageInput != "Y2F0LWJhc2U2NA==" {
		t.Fatalf("expected base64 image input, got %q", imageInput)
	}
}

func TestGenerateCompanionSceneSupportsB64JSONImageResponse(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	var imagePrompt string
	var mockAudioURL string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/compatible-mode/v1/chat/completions":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"character_name\":\"喵喵星友\",\"personality\":\"温柔\",\"dialog_text\":\"你好呀\",\"image_prompt\":\"猫咪卡通角色\"}"}}]}`))
		case r.Method == http.MethodPost && r.URL.Path == "/v1/byteplus/images/generations":
			var payload map[string]any
			if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
				t.Fatalf("decode image payload failed: %v", err)
			}
			imagePrompt, _ = payload["prompt"].(string)
			if payload["response_format"] != "b64_json" {
				t.Fatalf("expected response_format=b64_json, got %v", payload["response_format"])
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"data":[{"b64_json":"aGVsbG8="}]}`))
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/services/aigc/multimodal-generation/generation":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"status_code":200,"request_id":"req-voice-3","output":{"audio":{"url":"` + mockAudioURL + `"}}}`))
		case r.Method == http.MethodGet && r.URL.Path == "/mock-audio.wav":
			w.Header().Set("Content-Type", "audio/wav")
			_, _ = w.Write([]byte{7, 8, 9})
		default:
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
	}))
	defer server.Close()
	mockAudioURL = server.URL + "/mock-audio.wav"

	client, err := llm.NewClient(llm.Config{
		APIKey:              "test-key",
		BaseURL:             server.URL,
		ImageBaseURL:        server.URL,
		ImageResponseFormat: "b64_json",
		VoiceBaseURL:        server.URL,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	svc.SetLLMClient(client)

	resp, err := svc.GenerateCompanionScene(service.CompanionSceneRequest{
		ChildID:    "kid_b64",
		ChildAge:   8,
		ObjectType: "猫",
	})
	if err != nil {
		t.Fatalf("GenerateCompanionScene() error = %v", err)
	}
	if strings.TrimSpace(imagePrompt) == "" {
		t.Fatalf("expected image prompt")
	}
	if resp.CharacterImageURL != "" {
		t.Fatalf("expected image url to be empty for data-url image source, got %q", resp.CharacterImageURL)
	}
	if resp.CharacterImageBase64 != "aGVsbG8=" {
		t.Fatalf("expected base64 image payload, got %q", resp.CharacterImageBase64)
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

func TestChatCompanionTimeoutMappedError(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

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

	_, err = svc.ChatCompanion(service.CompanionChatRequest{
		ChildID:      "kid_timeout_1",
		ChildAge:     8,
		ObjectType:   "猫",
		ChildMessage: "为什么会这样？",
	})
	if !errors.Is(err, service.ErrCompanionTimeout) {
		t.Fatalf("expected ErrCompanionTimeout, got %v", err)
	}
}

func TestChatCompanionAddsEmotionHookForReply(t *testing.T) {
	t.Parallel()
	svc, _ := newTestService(t)

	var mockAudioURL string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/compatible-mode/v1/chat/completions":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"reply_text\":\"我是路灯，我们继续观察。\"}"}}]}`))
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/services/aigc/multimodal-generation/generation":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"status_code":200,"request_id":"req-chat-voice","output":{"audio":{"url":"` + mockAudioURL + `"}}}`))
		case r.Method == http.MethodGet && r.URL.Path == "/mock-chat-audio.wav":
			w.Header().Set("Content-Type", "audio/wav")
			_, _ = w.Write([]byte{9, 8, 7})
		default:
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
	}))
	defer server.Close()
	mockAudioURL = server.URL + "/mock-chat-audio.wav"

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

	resp, err := svc.ChatCompanion(service.CompanionChatRequest{
		ChildID:              "kid_chat_1",
		ChildAge:             8,
		ObjectType:           "路灯",
		CharacterName:        "云朵灯灯",
		CharacterPersonality: "温柔",
		ChildMessage:         "你会亮多久？",
	})
	if err != nil {
		t.Fatalf("ChatCompanion() error = %v", err)
	}
	if !strings.Contains(resp.ReplyText, "我是路灯") || !strings.Contains(resp.ReplyText, "我现在正开心") {
		t.Fatalf("expected reply to include identity+emotion hook, got %q", resp.ReplyText)
	}
	if strings.Contains(resp.ReplyText, "我是小冒险家") {
		t.Fatalf("expected object-centered identity, got %q", resp.ReplyText)
	}
	if strings.TrimSpace(resp.VoiceAudioBase64) == "" {
		t.Fatalf("expected non-empty voice base64")
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
