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
			Image     string `json:"image"`
			Watermark bool   `json:"watermark"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		if req.Watermark {
			t.Fatalf("expected watermark=false for generated images")
		}
		receivedImage = strings.TrimSpace(req.Image)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":[{"url":"https://img.example.com/companion.png"}]}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		APIKey:              "test-key",
		BaseURL:             server.URL,
		ImageBaseURL:        server.URL,
		ImageResponseFormat: "b64_json",
		VoiceBaseURL:        server.URL,
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

func TestGenerateCharacterImageWithDashScope(t *testing.T) {
	var gotPrompt string
	var gotImage string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/v1/services/aigc/multimodal-generation/generation" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		if strings.TrimSpace(r.Header.Get("x-app-id")) != "" || strings.TrimSpace(r.Header.Get("x-platform-id")) != "" {
			t.Fatalf("dashscope request should not include x-app-id/x-platform-id")
		}

		var req struct {
			Model string `json:"model"`
			Input struct {
				Messages []struct {
					Content []struct {
						Text  string `json:"text"`
						Image string `json:"image"`
					} `json:"content"`
				} `json:"messages"`
			} `json:"input"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		if req.Model != "wan2.6-image" {
			t.Fatalf("expected model=wan2.6-image, got %q", req.Model)
		}
		if len(req.Input.Messages) != 1 || len(req.Input.Messages[0].Content) != 2 {
			t.Fatalf("unexpected messages payload: %+v", req.Input.Messages)
		}
		gotPrompt = strings.TrimSpace(req.Input.Messages[0].Content[0].Text)
		gotImage = strings.TrimSpace(req.Input.Messages[0].Content[1].Image)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"output":{"choices":[{"message":{"content":[{"image":"https://img.example.com/dashscope.png"}]}}]}}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		APIKey:       "test-key",
		BaseURL:      server.URL,
		ImageBaseURL: server.URL + "/api/v1/services/aigc/multimodal-generation/generation",
		ImageModel:   "wan2.6-image",
		VoiceBaseURL: server.URL,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	client.httpClient = server.Client()

	got, err := client.GenerateCharacterImage(context.Background(), "绘本风猫咪", "https://example.com/cat.png")
	if err != nil {
		t.Fatalf("GenerateCharacterImage() error = %v", err)
	}
	if got != "https://img.example.com/dashscope.png" {
		t.Fatalf("unexpected image url: %s", got)
	}
	if gotPrompt != "绘本风猫咪" {
		t.Fatalf("unexpected prompt: %q", gotPrompt)
	}
	if gotImage != "https://example.com/cat.png" {
		t.Fatalf("unexpected image: %q", gotImage)
	}
}

func TestGenerateCharacterImageWithB64JSON(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/byteplus/images/generations" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var req struct {
			ResponseFormat string `json:"response_format"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		if req.ResponseFormat != "b64_json" {
			t.Fatalf("expected response_format=b64_json, got %q", req.ResponseFormat)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"data":[{"b64_json":"iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB"}]}`))
	}))
	defer server.Close()

	client, err := NewClient(Config{
		APIKey:              "test-key",
		BaseURL:             server.URL,
		ImageBaseURL:        server.URL,
		ImageResponseFormat: "b64_json",
		VoiceBaseURL:        server.URL,
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}
	client.httpClient = server.Client()

	got, err := client.GenerateCharacterImage(context.Background(), "卡通猫咪角色", "base64-cat-source")
	if err != nil {
		t.Fatalf("GenerateCharacterImage() error = %v", err)
	}
	if !strings.HasPrefix(got, "data:image/png;base64,") {
		t.Fatalf("expected data url image, got %q", got)
	}
}

func TestGenerateCharacterImageRetriesWithoutImageOnInvalidURL(t *testing.T) {
	var callCount int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/byteplus/images/generations" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		callCount++
		var req struct {
			Image string `json:"image"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode request body: %v", err)
		}

		w.Header().Set("Content-Type", "application/json")
		if callCount <= 2 {
			if strings.TrimSpace(req.Image) == "" {
				t.Fatalf("image candidate call should carry image param")
			}
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":"The parameter image specified in the request is not valid: invalid url specified.","code":400}`))
			return
		}

		if strings.TrimSpace(req.Image) != "" {
			t.Fatalf("retry should remove image param, got %q", req.Image)
		}
		_, _ = w.Write([]byte(`{"data":[{"url":"https://img.example.com/retry.png"}]}`))
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

	got, err := client.GenerateCharacterImage(context.Background(), "儿童绘本风猫咪", "base64-cat-source")
	if err != nil {
		t.Fatalf("GenerateCharacterImage() error = %v", err)
	}
	if got != "https://img.example.com/retry.png" {
		t.Fatalf("unexpected image url: %s", got)
	}
	if callCount != 3 {
		t.Fatalf("expected 3 calls (2 candidates + prompt retry), got %d", callCount)
	}
}

func TestNormalizeSourceImageInputCandidates(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name    string
		input   string
		outputs []string
	}{
		{
			name:  "raw base64",
			input: "YWJjMTIz",
			outputs: []string{
				"YWJjMTIz",
				"data:image/jpeg;base64,YWJjMTIz",
			},
		},
		{
			name:    "http url",
			input:   "http://example.com/cat.png",
			outputs: []string{"http://example.com/cat.png"},
		},
		{
			name:    "data url",
			input:   "data:image/png;base64,abcd",
			outputs: []string{"abcd", "data:image/png;base64,abcd"},
		},
		{
			name:    "trim spaces",
			input:   "  dGVzdA==  ",
			outputs: []string{"dGVzdA==", "data:image/jpeg;base64,dGVzdA=="},
		},
		{
			name:    "empty",
			input:   "   ",
			outputs: nil,
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got := normalizeSourceImageInputCandidates(tt.input)
			if len(got) != len(tt.outputs) {
				t.Fatalf("normalizeSourceImageInputCandidates() len=%d, want=%d (%v)", len(got), len(tt.outputs), got)
			}
			for i := range got {
				if got[i] != tt.outputs[i] {
					t.Fatalf("normalizeSourceImageInputCandidates()[%d] got %q, want %q", i, got[i], tt.outputs[i])
				}
			}
		})
	}
}

func TestResolveImageGenerationRequestURL(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name string
		in   string
		want string
	}{
		{
			name: "dashscope host default path",
			in:   "https://dashscope.aliyuncs.com",
			want: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
		},
		{
			name: "already full dashscope path",
			in:   "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
			want: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
		},
		{
			name: "byteplus host",
			in:   "https://api-image.charaboard.com",
			want: "https://api-image.charaboard.com/v1/byteplus/images/generations",
		},
		{
			name: "already full byteplus path",
			in:   "https://api-image.charaboard.com/v1/byteplus/images/generations",
			want: "https://api-image.charaboard.com/v1/byteplus/images/generations",
		},
		{
			name: "empty",
			in:   "",
			want: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
		},
	}

	for _, tt := range tests {
		tt := tt
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			got := resolveImageGenerationRequestURL(tt.in)
			if got != tt.want {
				t.Fatalf("resolveImageGenerationRequestURL(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

func TestSynthesizeSpeech(t *testing.T) {
	expected := []byte{1, 2, 3, 4, 5}
	var selectedVoice string
	var selectedModel string
	var selectedLanguage string
	var mockAudioURL string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/api/v1/services/aigc/multimodal-generation/generation":
			var req struct {
				Model string `json:"model"`
				Input struct {
					Text         string `json:"text"`
					Voice        string `json:"voice"`
					LanguageType string `json:"language_type"`
				} `json:"input"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode request body failed: %v", err)
			}
			if strings.TrimSpace(req.Input.Text) == "" {
				t.Fatalf("text should not be empty")
			}
			selectedModel = strings.TrimSpace(req.Model)
			selectedVoice = strings.TrimSpace(req.Input.Voice)
			selectedLanguage = strings.TrimSpace(req.Input.LanguageType)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"status_code":200,"request_id":"req-1","output":{"audio":{"url":"` + mockAudioURL + `"}}}`))
		case r.Method == http.MethodGet && r.URL.Path == "/mock-audio.wav":
			w.Header().Set("Content-Type", "audio/wav")
			_, _ = w.Write(expected)
		default:
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
	}))
	defer server.Close()
	mockAudioURL = server.URL + "/mock-audio.wav"

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

	audio, mime, err := client.SynthesizeSpeech(context.Background(), "你好，小朋友", "猫")
	if err != nil {
		t.Fatalf("SynthesizeSpeech() error = %v", err)
	}
	if mime != "audio/wav" {
		t.Fatalf("expected audio/wav, got %s", mime)
	}
	if string(audio) != string(expected) {
		t.Fatalf("unexpected audio bytes")
	}
	if selectedModel != "qwen3-tts-flash" {
		t.Fatalf("expected qwen3-tts-flash, got %q", selectedModel)
	}
	if selectedVoice == "" {
		t.Fatalf("voice should not be empty")
	}
	if selectedLanguage != "Chinese" {
		t.Fatalf("expected Chinese language type, got %q", selectedLanguage)
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

func TestDownloadImageDataURL(t *testing.T) {
	client, err := NewClient(Config{
		APIKey: "test-key",
	})
	if err != nil {
		t.Fatalf("NewClient() error = %v", err)
	}

	body, mime, err := client.DownloadImage(context.Background(), "data:image/png;base64,aGVsbG8=")
	if err != nil {
		t.Fatalf("DownloadImage() error = %v", err)
	}
	if mime != "image/png" {
		t.Fatalf("expected image/png, got %q", mime)
	}
	if string(body) != "hello" {
		t.Fatalf("unexpected decoded data: %q", string(body))
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
		if r.URL.Path != "/compatible-mode/v1/chat/completions" {
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
