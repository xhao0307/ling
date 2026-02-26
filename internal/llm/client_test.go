package llm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestParseVisionRecognizeResultFromTruncatedJSON(t *testing.T) {
	content := "```json\n{\"object_type\":\"cat\",\"raw_label\n```"
	got, err := parseVisionRecognizeResult(content)
	if err != nil {
		t.Fatalf("parseVisionRecognizeResult() error = %v", err)
	}
	if got.ObjectType != "cat" {
		t.Fatalf("expected object_type=cat, got %q", got.ObjectType)
	}
	if got.RawLabel != "cat" {
		t.Fatalf("expected raw_label fallback to cat, got %q", got.RawLabel)
	}
}

func TestParseVisionRecognizeResultFromBrokenJSONStillReadsFields(t *testing.T) {
	content := "{\"object_type\":\"traffic-light\",\"raw_label\":\"交通信号灯\",\"reason\":\"十字路口可见\""
	got, err := parseVisionRecognizeResult(content)
	if err != nil {
		t.Fatalf("parseVisionRecognizeResult() error = %v", err)
	}
	if got.ObjectType != "traffic_light" {
		t.Fatalf("expected normalized object_type=traffic_light, got %q", got.ObjectType)
	}
	if got.RawLabel != "交通信号灯" {
		t.Fatalf("expected raw_label=交通信号灯, got %q", got.RawLabel)
	}
}

func TestParseAnswerJudgeResultWithBoolean(t *testing.T) {
	content := `{"correct":true,"reason":"语义一致"}`
	got, err := parseAnswerJudgeResult(content)
	if err != nil {
		t.Fatalf("parseAnswerJudgeResult() error = %v", err)
	}
	if !got.Correct {
		t.Fatalf("expected correct=true, got false")
	}
	if got.Reason != "语义一致" {
		t.Fatalf("expected reason=语义一致, got %q", got.Reason)
	}
}

func TestParseAnswerJudgeResultWithChineseBoolString(t *testing.T) {
	content := `{"correct":"对","reason":"核心概念匹配"}`
	got, err := parseAnswerJudgeResult(content)
	if err != nil {
		t.Fatalf("parseAnswerJudgeResult() error = %v", err)
	}
	if !got.Correct {
		t.Fatalf("expected correct=true, got false")
	}
	if got.Reason != "核心概念匹配" {
		t.Fatalf("expected reason=核心概念匹配, got %q", got.Reason)
	}
}

func TestJudgeAnswerOnlyUsesQuestionAndAnswer(t *testing.T) {
	var userPrompt string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/compatible-mode/v1/chat/completions" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var req struct {
			Messages []struct {
				Role    string `json:"role"`
				Content string `json:"content"`
			} `json:"messages"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode request body: %v", err)
		}
		for _, msg := range req.Messages {
			if msg.Role == "user" {
				userPrompt = msg.Content
				break
			}
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"correct\":true,\"reason\":\"语义匹配\"}"}}]}`))
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

	result, err := client.JudgeAnswer(context.Background(), "这个动物会汪汪叫吗？", "会")
	if err != nil {
		t.Fatalf("JudgeAnswer() error = %v", err)
	}
	if !result.Correct {
		t.Fatalf("expected correct=true")
	}
	if !strings.Contains(userPrompt, "题目:这个动物会汪汪叫吗？") || !strings.Contains(userPrompt, "孩子回答:会") {
		t.Fatalf("expected user prompt to contain question and answer only, got %q", userPrompt)
	}
	if strings.Contains(userPrompt, "标准答案") || strings.Contains(userPrompt, "孩子年龄") {
		t.Fatalf("expected user prompt not to contain extra fields, got %q", userPrompt)
	}
}
