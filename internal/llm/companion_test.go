package llm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestParseCompanionScene(t *testing.T) {
	content := `{"character_name":"云朵灯灯","personality":"温柔好奇","dialog_text":"你好呀，我们一起观察这盏路灯吧！","image_prompt":"儿童卡通风，拟人化路灯角色，晴天街道，温暖光线"}`
	scene, err := parseCompanionScene(content)
	if err != nil {
		t.Fatalf("parseCompanionScene() error = %v", err)
	}
	if scene.CharacterName != "云朵灯灯" {
		t.Fatalf("expected character_name=云朵灯灯, got %q", scene.CharacterName)
	}
	if scene.DialogText == "" || scene.ImagePrompt == "" {
		t.Fatalf("expected non-empty dialog/image prompt")
	}
}

func TestParseCompanionSceneWithTrailingJSON(t *testing.T) {
	content := `{"character_name":"小圆","personality":"活泼","dialog_text":"一起观察吧","image_prompt":"卡通风格"}{"extra":"ignored"}`
	scene, err := parseCompanionScene(content)
	if err != nil {
		t.Fatalf("parseCompanionScene() error = %v", err)
	}
	if scene.CharacterName != "小圆" {
		t.Fatalf("expected character_name=小圆, got %q", scene.CharacterName)
	}
}

func TestGenerateCharacterImage(t *testing.T) {
	var receivedImage string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/byteplus/images/generations" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if !strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") {
			t.Fatalf("missing bearer auth")
		}
		var req struct {
			Image string `json:"image"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		receivedImage = strings.TrimSpace(req.Image)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":[{"url":"https://img.example.com/companion.png"}]}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		APIKey:       "test-key",
		BaseURL:      server.URL,
		ImageBaseURL: server.URL,
		VoiceBaseURL: server.URL,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	client.httpClient = server.Client()

	got, err := client.GenerateCharacterImage(context.Background(), "卡通路灯角色", "base64-cat-source")
	if err != nil {
		t.Fatalf("GenerateCharacterImage() error = %v", err)
	}
	if got != "https://img.example.com/companion.png" {
		t.Fatalf("unexpected image url: %s", got)
	}
	if receivedImage != "base64-cat-source" {
		t.Fatalf("expected source image to be forwarded, got %q", receivedImage)
	}
}

func TestSynthesizeSpeech(t *testing.T) {
	expected := []byte{1, 2, 3, 4, 5}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/elevenlabs/tts/generate" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if got := r.URL.Query().Get("output_format"); got == "" {
			t.Fatalf("output_format should not be empty")
		}
		w.Header().Set("Content-Type", "audio/mpeg")
		_, _ = w.Write(expected)
	}))
	defer server.Close()

	client, err := NewClient(Config{
		APIKey:       "test-key",
		BaseURL:      server.URL,
		ImageBaseURL: server.URL,
		VoiceBaseURL: server.URL,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	client.httpClient = server.Client()

	audio, mime, err := client.SynthesizeSpeech(context.Background(), "你好，小朋友")
	if err != nil {
		t.Fatalf("SynthesizeSpeech() error = %v", err)
	}
	if mime != "audio/mpeg" {
		t.Fatalf("expected audio/mpeg, got %s", mime)
	}
	if string(audio) != string(expected) {
		t.Fatalf("unexpected audio bytes")
	}
}

func TestDownloadImage(t *testing.T) {
	expected := []byte{9, 8, 7, 6}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/img.png" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "image/png")
		_, _ = w.Write(expected)
	}))
	defer server.Close()

	client, err := NewClient(Config{
		APIKey:  "test-key",
		BaseURL: server.URL,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	client.httpClient = server.Client()

	body, mime, err := client.DownloadImage(context.Background(), server.URL+"/img.png")
	if err != nil {
		t.Fatalf("DownloadImage() error = %v", err)
	}
	if mime != "image/png" {
		t.Fatalf("expected image/png, got %q", mime)
	}
	if string(body) != string(expected) {
		t.Fatalf("unexpected image bytes")
	}
}

func TestParseCompanionReply(t *testing.T) {
	content := `{"reply_text":"你观察得真仔细，我们再看看它的颜色变化吧。"}`
	reply, err := parseCompanionReply(content)
	if err != nil {
		t.Fatalf("parseCompanionReply() error = %v", err)
	}
	if reply.ReplyText == "" {
		t.Fatalf("expected non-empty reply text")
	}
}

func TestParseCompanionReplyWithTrailingJSON(t *testing.T) {
	content := `{"reply_text":"我们继续探索。"}{"extra":"ignored"}`
	reply, err := parseCompanionReply(content)
	if err != nil {
		t.Fatalf("parseCompanionReply() error = %v", err)
	}
	if reply.ReplyText != "我们继续探索。" {
		t.Fatalf("unexpected reply text: %q", reply.ReplyText)
	}
}

func TestGenerateCompanionReply(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"reply_text\":\"我们一起数数它有几个灯吧！\"}"}}]}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		APIKey:  "test-key",
		BaseURL: server.URL,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	client.httpClient = server.Client()

	reply, err := client.GenerateCompanionReply(context.Background(), CompanionReplyRequest{
		ObjectType:           "路灯",
		ChildAge:             8,
		CharacterName:        "云朵灯灯",
		CharacterPersonality: "温柔好奇",
		Weather:              "晴天",
		Environment:          "小区道路",
		ObjectTraits:         "暖光",
		History:              []string{"角色：你好呀", "孩子：你好"},
		ChildMessage:         "为什么它会亮？",
	})
	if err != nil {
		t.Fatalf("GenerateCompanionReply() error = %v", err)
	}
	if reply.ReplyText == "" {
		t.Fatalf("expected non-empty reply text")
	}
}
