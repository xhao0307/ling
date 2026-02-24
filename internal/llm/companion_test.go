package llm

import (
	"context"
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

func TestGenerateCharacterImage(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/byteplus/images/generations" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if !strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") {
			t.Fatalf("missing bearer auth")
		}
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

	got, err := client.GenerateCharacterImage(context.Background(), "卡通路灯角色")
	if err != nil {
		t.Fatalf("GenerateCharacterImage() error = %v", err)
	}
	if got != "https://img.example.com/companion.png" {
		t.Fatalf("unexpected image url: %s", got)
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
