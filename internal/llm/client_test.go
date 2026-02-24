package llm

import "testing"

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
