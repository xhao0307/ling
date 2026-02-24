package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"strings"
	"time"
)

var (
	ErrInvalidResponse = errors.New("invalid llm response")
)

type Config struct {
	BaseURL             string
	APIKey              string
	AppID               string
	PlatformID          string
	VisionGPTType       int
	TextGPTType         int
	Timeout             time.Duration
	ImageBaseURL        string
	ImageAPIKey         string
	ImageModel          string
	ImageResponseFormat string
	VoiceBaseURL        string
	VoiceAPIKey         string
	VoiceID             string
	VoiceModelID        string
	VoiceLangCode       string
	VoiceFormat         string
}

type Client struct {
	baseURL             string
	apiKey              string
	appID               string
	platformID          string
	visionGPTType       int
	textGPTType         int
	timeout             time.Duration
	httpClient          *http.Client
	imageBaseURL        string
	imageAPIKey         string
	imageModel          string
	imageResponseFormat string
	voiceBaseURL        string
	voiceAPIKey         string
	voiceID             string
	voiceModelID        string
	voiceLangCode       string
	voiceFormat         string
}

type RecognizeResult struct {
	ObjectType string
	RawLabel   string
	Reason     string
}

type LearningContent struct {
	Fact       string
	QuizQ      string
	QuizA      string
	Dialogues  []string
	RawContent string
}

type AnswerJudgeResult struct {
	Correct    bool
	Reason     string
	RawContent string
}

func NewClient(cfg Config) (*Client, error) {
	if strings.TrimSpace(cfg.APIKey) == "" {
		return nil, errors.New("llm api key is required")
	}
	baseURL := strings.TrimSpace(cfg.BaseURL)
	if baseURL == "" {
		baseURL = "https://api-chat.charaboard.com"
	}
	if cfg.VisionGPTType == 0 {
		cfg.VisionGPTType = 8102
	}
	if cfg.TextGPTType == 0 {
		cfg.TextGPTType = 8602
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 20 * time.Second
	}
	imageBaseURL := strings.TrimSpace(cfg.ImageBaseURL)
	if imageBaseURL == "" {
		imageBaseURL = "https://api-image.charaboard.com"
	}
	imageAPIKey := strings.TrimSpace(cfg.ImageAPIKey)
	if imageAPIKey == "" {
		imageAPIKey = strings.TrimSpace(cfg.APIKey)
	}
	imageModel := strings.TrimSpace(cfg.ImageModel)
	if imageModel == "" {
		imageModel = "seedream-4-0-250828"
	}
	imageResponseFormat := strings.ToLower(strings.TrimSpace(cfg.ImageResponseFormat))
	if imageResponseFormat == "" {
		imageResponseFormat = "b64_json"
	}
	if imageResponseFormat != "url" && imageResponseFormat != "b64_json" {
		imageResponseFormat = "b64_json"
	}
	voiceBaseURL := strings.TrimSpace(cfg.VoiceBaseURL)
	if voiceBaseURL == "" {
		voiceBaseURL = "https://api-voice.charaboard.com"
	}
	voiceAPIKey := strings.TrimSpace(cfg.VoiceAPIKey)
	if voiceAPIKey == "" {
		voiceAPIKey = strings.TrimSpace(cfg.APIKey)
	}
	voiceID := strings.TrimSpace(cfg.VoiceID)
	if voiceID == "" {
		voiceID = "Xb7hH8MSUJpSbSDYk0k2"
	}
	voiceModelID := strings.TrimSpace(cfg.VoiceModelID)
	if voiceModelID == "" {
		voiceModelID = "eleven_multilingual_v2"
	}
	voiceLangCode := strings.TrimSpace(cfg.VoiceLangCode)
	if voiceLangCode == "" {
		voiceLangCode = "zh"
	}
	voiceFormat := strings.TrimSpace(cfg.VoiceFormat)
	if voiceFormat == "" {
		voiceFormat = "mp3_44100_128"
	}
	appID := strings.TrimSpace(cfg.AppID)
	if appID == "" {
		appID = "4"
	}
	platformID := strings.TrimSpace(cfg.PlatformID)
	if platformID == "" {
		platformID = "5"
	}

	return &Client{
		baseURL:             strings.TrimRight(baseURL, "/"),
		apiKey:              strings.TrimSpace(cfg.APIKey),
		appID:               appID,
		platformID:          platformID,
		visionGPTType:       cfg.VisionGPTType,
		textGPTType:         cfg.TextGPTType,
		timeout:             cfg.Timeout,
		httpClient:          &http.Client{},
		imageBaseURL:        strings.TrimRight(imageBaseURL, "/"),
		imageAPIKey:         imageAPIKey,
		imageModel:          imageModel,
		imageResponseFormat: imageResponseFormat,
		voiceBaseURL:        strings.TrimRight(voiceBaseURL, "/"),
		voiceAPIKey:         voiceAPIKey,
		voiceID:             voiceID,
		voiceModelID:        voiceModelID,
		voiceLangCode:       voiceLangCode,
		voiceFormat:         voiceFormat,
	}, nil
}

func (c *Client) RecognizeObject(ctx context.Context, imageBase64 string, imageURL string) (RecognizeResult, error) {
	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	imageRef := strings.TrimSpace(imageURL)
	if imageRef == "" {
		base64Content := strings.TrimSpace(imageBase64)
		if base64Content == "" {
			return RecognizeResult{}, errors.New("image is required")
		}
		if strings.HasPrefix(base64Content, "data:image") {
			imageRef = base64Content
		} else {
			imageRef = "data:image/jpeg;base64," + base64Content
		}
	}

	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		body := c.buildVisionRequestBody(imageRef, attempt > 0)
		raw, err := c.doJSON(ctx, "/v2/chat/completions", body)
		if err != nil {
			lastErr = err
			continue
		}

		content, err := extractAssistantContent(raw)
		if err != nil {
			lastErr = err
			continue
		}

		result, err := parseVisionRecognizeResult(content)
		if err == nil {
			return result, nil
		}
		lastErr = fmt.Errorf("%w; raw=%s", err, truncateText(content, 240))
	}
	if lastErr == nil {
		lastErr = ErrInvalidResponse
	}
	return RecognizeResult{}, lastErr
}

func (c *Client) GenerateLearningContent(ctx context.Context, objectType string, childAge int, spiritName string, personality string) (LearningContent, error) {
	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	body := map[string]any{
		"gpt_type": c.textGPTType,
		"messages": []map[string]any{
			{
				"role":    "system",
				"content": "你是儿童城市科普助手。请输出简洁中文JSON，不要输出任何额外说明。",
			},
			{
				"role":    "user",
				"content": fmt.Sprintf("孩子年龄:%d; 物体类型:%s; 精灵名字:%s; 精灵性格:%s。请生成JSON字段: fact(1句), quiz_question(1句), quiz_answer(短语), dialogues(3-4句数组)。", childAge, objectType, spiritName, personality),
			},
		},
		"temperature": 0.7,
		"max_tokens":  600,
		"response_format": map[string]any{
			"type": "json_object",
		},
	}

	raw, err := c.doJSON(ctx, "/v1/chat/completions", body)
	if err != nil {
		return LearningContent{}, err
	}
	content, err := extractAssistantContent(raw)
	if err != nil {
		return LearningContent{}, err
	}

	var parsed struct {
		Fact      string   `json:"fact"`
		QuizQ     string   `json:"quiz_question"`
		QuizA     string   `json:"quiz_answer"`
		Dialogues []string `json:"dialogues"`
	}
	if err := json.Unmarshal([]byte(extractJSONPayload(content)), &parsed); err != nil {
		return LearningContent{}, fmt.Errorf("parse text generation result failed: %w", err)
	}

	result := LearningContent{
		Fact:       strings.TrimSpace(parsed.Fact),
		QuizQ:      strings.TrimSpace(parsed.QuizQ),
		QuizA:      strings.TrimSpace(parsed.QuizA),
		Dialogues:  sanitizeDialogues(parsed.Dialogues),
		RawContent: content,
	}
	if result.Fact == "" || result.QuizQ == "" || result.QuizA == "" {
		return LearningContent{}, ErrInvalidResponse
	}
	return result, nil
}

func (c *Client) JudgeAnswer(ctx context.Context, question string, expectedAnswer string, givenAnswer string, childAge int) (AnswerJudgeResult, error) {
	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	body := map[string]any{
		"gpt_type": c.textGPTType,
		"messages": []map[string]any{
			{
				"role":    "system",
				"content": "你是儿童问答判题助手。请结合题目语义判断作答是否正确，允许同义表达、近义词和口语化表达。仅输出 JSON。",
			},
			{
				"role": "user",
				"content": fmt.Sprintf(
					"孩子年龄:%d\n题目:%s\n标准答案:%s\n孩子回答:%s\n请输出 JSON 字段: correct(boolean), reason(string，简体中文，20字以内)。",
					childAge,
					strings.TrimSpace(question),
					strings.TrimSpace(expectedAnswer),
					strings.TrimSpace(givenAnswer),
				),
			},
		},
		"temperature": 0.2,
		"max_tokens":  180,
		"response_format": map[string]any{
			"type": "json_object",
		},
	}

	raw, err := c.doJSON(ctx, "/v1/chat/completions", body)
	if err != nil {
		return AnswerJudgeResult{}, err
	}
	content, err := extractAssistantContent(raw)
	if err != nil {
		return AnswerJudgeResult{}, err
	}
	result, err := parseAnswerJudgeResult(content)
	if err != nil {
		return AnswerJudgeResult{}, err
	}
	result.RawContent = content
	return result, nil
}

func (c *Client) doJSON(ctx context.Context, path string, payload any) ([]byte, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-app-id", c.appID)
	req.Header.Set("x-platform-id", c.platformID)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("llm request failed, status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}
	return respBody, nil
}

func (c *Client) buildVisionRequestBody(imageRef string, strict bool) map[string]any {
	prompt := `你在服务中国用户，请全部使用简体中文表达。
识别图中最主要的物体，仅输出一行 JSON，不要 markdown，不要解释。
输出格式：
{"object_type":"类别标识","raw_label":"中文标签","reason":"中文一句话识别依据"}

字段要求：
1) raw_label: 必须是中文常用叫法（例如：猫、汽车、建筑、路牌）。
2) reason: 必须是中文且简洁。
3) object_type:
   - 不限制固定枚举，不要输出英文枚举；
   - 统一使用中文短词（例如：猫、狗、公交车、红绿灯、井盖）。`
	if strict {
		prompt += "\n如果无法识别，object_type 设为 \"unknown\"，raw_label 设为“未知物体”。"
	}

	return map[string]any{
		"gpt_type": c.visionGPTType,
		"messages": []map[string]any{
			{
				"role": "user",
				"content": []map[string]any{
					{
						"type": "text",
						"text": prompt,
					},
					{
						"type": "image_url",
						"image_url": map[string]string{
							"url": imageRef,
						},
					},
				},
			},
		},
		"temperature": 0.1,
		"max_tokens":  320,
	}
}

func extractAssistantContent(raw []byte) (string, error) {
	var resp struct {
		Choices []struct {
			Message struct {
				Content any `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(raw, &resp); err != nil {
		return "", err
	}
	if len(resp.Choices) == 0 {
		return "", ErrInvalidResponse
	}
	content := resp.Choices[0].Message.Content
	switch v := content.(type) {
	case string:
		return strings.TrimSpace(v), nil
	case []any:
		parts := make([]string, 0, len(v))
		for _, item := range v {
			m, ok := item.(map[string]any)
			if !ok {
				continue
			}
			if text, ok := m["text"].(string); ok {
				parts = append(parts, text)
			}
		}
		if len(parts) == 0 {
			return "", ErrInvalidResponse
		}
		return strings.TrimSpace(strings.Join(parts, "\n")), nil
	default:
		return "", ErrInvalidResponse
	}
}

func extractJSONPayload(content string) string {
	trimmed := strings.TrimSpace(content)
	if trimmed == "" {
		return "{}"
	}
	if strings.HasPrefix(trimmed, "```") {
		trimmed = strings.TrimPrefix(trimmed, "```json")
		trimmed = strings.TrimPrefix(trimmed, "```")
		trimmed = strings.TrimSuffix(trimmed, "```")
		trimmed = strings.TrimSpace(trimmed)
	}
	start := strings.Index(trimmed, "{")
	end := strings.LastIndex(trimmed, "}")
	if start >= 0 && end >= start {
		return trimmed[start : end+1]
	}
	return trimmed
}

func parseVisionRecognizeResult(content string) (RecognizeResult, error) {
	trimmed := strings.TrimSpace(content)
	if trimmed == "" {
		return RecognizeResult{}, fmt.Errorf("parse vision result failed: empty content")
	}

	var parsed struct {
		ObjectType string `json:"object_type"`
		RawLabel   string `json:"raw_label"`
		Reason     string `json:"reason"`
	}
	if err := json.Unmarshal([]byte(extractJSONPayload(trimmed)), &parsed); err == nil {
		objectType := normalizeObjectType(parsed.ObjectType)
		// 接受任意 object_type，不再限制在支持列表中
		if objectType != "" && objectType != "unknown" {
			rawLabel := strings.TrimSpace(parsed.RawLabel)
			if rawLabel == "" {
				rawLabel = objectType
			}
			return RecognizeResult{
				ObjectType: objectType,
				RawLabel:   rawLabel,
				Reason:     strings.TrimSpace(parsed.Reason),
			}, nil
		}
		// 如果是 unknown，也返回结果，让上层处理
		if objectType == "unknown" {
			rawLabel := strings.TrimSpace(parsed.RawLabel)
			if rawLabel == "" {
				rawLabel = "unknown"
			}
			return RecognizeResult{
				ObjectType: "unknown",
				RawLabel:   rawLabel,
				Reason:     strings.TrimSpace(parsed.Reason),
			}, nil
		}
	}

	// 容错: 当返回被 markdown 包裹或 JSON 被截断时，尽量提取已输出字段。
	payload := extractJSONPayload(trimmed)
	objectType := normalizeObjectType(extractJSONField(payload, "object_type"))
	if objectType == "" {
		objectType = normalizeObjectType(extractJSONField(trimmed, "object_type"))
	}
	if objectType != "" {
		rawLabel := strings.TrimSpace(extractJSONField(payload, "raw_label"))
		if rawLabel == "" {
			rawLabel = strings.TrimSpace(extractJSONField(trimmed, "raw_label"))
		}
		if rawLabel == "" {
			rawLabel = objectType
		}
		reason := strings.TrimSpace(extractJSONField(payload, "reason"))
		if reason == "" {
			reason = strings.TrimSpace(extractJSONField(trimmed, "reason"))
		}
		return RecognizeResult{
			ObjectType: objectType,
			RawLabel:   rawLabel,
			Reason:     reason,
		}, nil
	}

	// 尝试从文本中推断（保留向后兼容）
	if objectType := inferObjectTypeFromText(trimmed); objectType != "" {
		return RecognizeResult{
			ObjectType: objectType,
			RawLabel:   objectType,
			Reason:     strings.TrimSpace(trimmed),
		}, nil
	}

	return RecognizeResult{}, fmt.Errorf("parse vision result failed: model output is not valid JSON")
}

func parseAnswerJudgeResult(content string) (AnswerJudgeResult, error) {
	trimmed := strings.TrimSpace(content)
	if trimmed == "" {
		return AnswerJudgeResult{}, fmt.Errorf("parse answer judge result failed: empty content")
	}

	payload := extractJSONPayload(trimmed)
	var parsed map[string]any
	if err := json.Unmarshal([]byte(payload), &parsed); err == nil {
		if correct, ok := toBool(parsed["correct"]); ok {
			reason := strings.TrimSpace(fmt.Sprint(parsed["reason"]))
			if reason == "<nil>" {
				reason = ""
			}
			return AnswerJudgeResult{
				Correct: correct,
				Reason:  reason,
			}, nil
		}
	}

	if correctStr := extractJSONField(payload, "correct"); correctStr != "" {
		if correct, ok := parseBoolLike(correctStr); ok {
			return AnswerJudgeResult{
				Correct: correct,
				Reason:  strings.TrimSpace(extractJSONField(payload, "reason")),
			}, nil
		}
	}

	return AnswerJudgeResult{}, fmt.Errorf("parse answer judge result failed: model output is not valid JSON")
}

func toBool(v any) (bool, bool) {
	switch x := v.(type) {
	case bool:
		return x, true
	case string:
		return parseBoolLike(x)
	case float64:
		if x == 1 {
			return true, true
		}
		if x == 0 {
			return false, true
		}
	}
	return false, false
}

func parseBoolLike(v string) (bool, bool) {
	normalized := strings.ToLower(strings.TrimSpace(v))
	switch normalized {
	case "true", "1", "yes", "y", "对", "正确", "是":
		return true, true
	case "false", "0", "no", "n", "错", "错误", "否":
		return false, true
	default:
		return false, false
	}
}

func extractJSONField(content string, key string) string {
	key = strings.TrimSpace(key)
	if key == "" {
		return ""
	}
	quotedPattern := fmt.Sprintf(`(?is)"%s"\s*:\s*"([^"]*)"`, regexp.QuoteMeta(key))
	if m := regexp.MustCompile(quotedPattern).FindStringSubmatch(content); len(m) == 2 {
		return strings.TrimSpace(m[1])
	}
	unquotedPattern := fmt.Sprintf(`(?is)"%s"\s*:\s*([A-Za-z0-9_\-]+)`, regexp.QuoteMeta(key))
	if m := regexp.MustCompile(unquotedPattern).FindStringSubmatch(content); len(m) == 2 {
		return strings.TrimSpace(m[1])
	}
	return ""
}

func inferObjectTypeFromText(content string) string {
	c := strings.ToLower(content)
	c = strings.ReplaceAll(c, "-", "_")

	checks := []struct {
		objectType string
		keywords   []string
	}{
		{"traffic_light", []string{"traffic_light", "traffic light", "signal light", "stoplight", "traffic signal", "红绿灯", "信号灯"}},
		{"road_sign", []string{"road_sign", "road sign", "traffic sign", "signpost", "street sign", "路牌", "标志牌", "交通标志"}},
		{"mailbox", []string{"mailbox", "postbox", "post box", "邮箱", "邮筒"}},
		{"manhole", []string{"manhole", "man hole", "well_cover", "drain_cover", "井盖", "窨井盖", "下水道盖"}},
		{"tree", []string{"tree", "street_tree", "树", "树木"}},
	}
	for _, item := range checks {
		for _, keyword := range item.keywords {
			if strings.Contains(c, keyword) {
				return item.objectType
			}
		}
	}
	return ""
}

func truncateText(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) <= n {
		return s
	}
	return s[:n] + "..."
}

func normalizeObjectType(v string) string {
	v = strings.ToLower(strings.TrimSpace(v))
	v = strings.ReplaceAll(v, "-", "_")
	v = strings.ReplaceAll(v, " ", "_")
	synonyms := map[string]string{
		"post_box":       "mailbox",
		"street_tree":    "tree",
		"well_cover":     "manhole",
		"drain_cover":    "manhole",
		"traffic_sign":   "road_sign",
		"signal_light":   "traffic_light",
		"stoplight":      "traffic_light",
		"traffic_signal": "traffic_light",
	}
	if mapped, ok := synonyms[v]; ok {
		return mapped
	}
	return v
}

func supportedObjectTypes() map[string]struct{} {
	return map[string]struct{}{
		"mailbox":       {},
		"tree":          {},
		"manhole":       {},
		"road_sign":     {},
		"traffic_light": {},
	}
}

func sanitizeDialogues(input []string) []string {
	result := make([]string, 0, len(input))
	for _, line := range input {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		result = append(result, line)
	}
	return result
}
