package llm

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"strings"
	"time"
)

var (
	ErrImageCapabilityUnavailable = errors.New("未配置生图能力")
	ErrVoiceCapabilityUnavailable = errors.New("未配置语音合成能力")
)

type CompanionSceneRequest struct {
	ObjectType   string
	ChildAge     int
	Weather      string
	Environment  string
	ObjectTraits string
}

type CompanionScene struct {
	CharacterName        string
	CharacterPersonality string
	DialogText           string
	ImagePrompt          string
	RawContent           string
}

type CompanionReplyRequest struct {
	ObjectType           string
	ChildAge             int
	CharacterName        string
	CharacterPersonality string
	Weather              string
	Environment          string
	ObjectTraits         string
	History              []string
	ChildMessage         string
}

type CompanionReply struct {
	ReplyText  string
	RawContent string
}

const (
	bytePlusImageGenerationPath  = "/v1/byteplus/images/generations"
	dashScopeImageGenerationPath = "/api/v1/services/aigc/multimodal-generation/generation"
	dashScopeTTSGenerationPath   = "/api/v1/services/aigc/multimodal-generation/generation"
	companionHistoryLimit        = 8
)

func (c *Client) GenerateCompanionScene(ctx context.Context, req CompanionSceneRequest) (CompanionScene, error) {
	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()
	promptSpec := renderCompanionPromptSpec(c.companionPromptSpec, req.ChildAge, req.ObjectType)

	body := map[string]any{
		"model": c.companionModel,
		"messages": []map[string]any{
			{
				"role":    "system",
				"content": buildCompanionSceneSystemPromptWithSpec(promptSpec),
			},
			{
				"role":    "user",
				"content": buildCompanionSceneUserPromptWithSpec(req, promptSpec),
			},
		},
		"temperature": 0.8,
		"max_tokens":  600,
		"response_format": map[string]any{
			"type": "json_object",
		},
	}

	raw, err := c.doJSON(ctx, c.chatCompletionsPath, body)
	if err != nil {
		return CompanionScene{}, err
	}
	content, err := extractAssistantContent(raw)
	if err != nil {
		return CompanionScene{}, err
	}
	scene, err := parseCompanionScene(content)
	if err != nil {
		return CompanionScene{}, err
	}
	scene.RawContent = content
	return scene, nil
}

func (c *Client) GenerateCharacterImage(ctx context.Context, imagePrompt string, sourceImage string) (string, error) {
	if strings.TrimSpace(c.imageAPIKey) == "" {
		return "", ErrImageCapabilityUnavailable
	}
	// 这里不再额外套超时，避免上游慢请求在客户端提前被 context cancel。
	// 调用方可按需在更高层控制超时策略。
	requestURL := resolveImageGenerationRequestURL(c.imageBaseURL)
	trimmedPrompt := strings.TrimSpace(imagePrompt)
	trimmedSourceImage := strings.TrimSpace(sourceImage)

	if isDashScopeImageRequestURL(requestURL) {
		body := buildDashScopeImageGenerationBody(c.imageModel, trimmedPrompt, trimmedSourceImage)
		respBody, _, err := c.doMediaJSON(ctx, requestURL, c.imageAPIKey, body)
		if err != nil {
			return "", err
		}
		return parseGeneratedImageValue(respBody)
	}

	body := map[string]any{
		"model":           c.imageModel,
		"prompt":          trimmedPrompt,
		"n":               1,
		"response_format": c.imageResponseFormat,
		"size":            "2K",
		"stream":          false,
		"watermark":       false,
	}
	candidates := normalizeSourceImageInputCandidates(trimmedSourceImage)
	var (
		respBody []byte
		err      error
	)
	if len(candidates) > 0 {
		for _, candidate := range candidates {
			body["image"] = candidate
			respBody, _, err = c.doMediaJSON(ctx, requestURL, c.imageAPIKey, body)
			if err == nil {
				break
			}
			if !isInvalidImageParamError(err) {
				return "", err
			}
		}
		if err != nil {
			// 某些上游实现只接受公网 URL 作为 image 参数。候选格式均失败时，自动降级为纯 prompt 生图重试一次。
			delete(body, "image")
			respBody, _, err = c.doMediaJSON(ctx, requestURL, c.imageAPIKey, body)
		}
	} else {
		respBody, _, err = c.doMediaJSON(ctx, requestURL, c.imageAPIKey, body)
	}
	if err != nil {
		return "", err
	}
	return parseGeneratedImageValue(respBody)
}

func resolveImageGenerationRequestURL(baseURL string) string {
	trimmed := strings.TrimSpace(baseURL)
	if trimmed == "" {
		return "https://dashscope.aliyuncs.com" + dashScopeImageGenerationPath
	}
	lower := strings.ToLower(trimmed)
	if strings.Contains(lower, "/api/v1/services/aigc/multimodal-generation/generation") ||
		strings.Contains(lower, "/v1/byteplus/images/generations") {
		return strings.TrimRight(trimmed, "/")
	}
	if strings.Contains(lower, "dashscope.aliyuncs.com") {
		return strings.TrimRight(trimmed, "/") + dashScopeImageGenerationPath
	}
	return strings.TrimRight(trimmed, "/") + bytePlusImageGenerationPath
}

func isDashScopeImageRequestURL(requestURL string) bool {
	lower := strings.ToLower(strings.TrimSpace(requestURL))
	if lower == "" {
		return false
	}
	return strings.Contains(lower, "dashscope.aliyuncs.com") ||
		strings.Contains(lower, "/api/v1/services/aigc/multimodal-generation/generation")
}

func buildDashScopeImageGenerationBody(model string, prompt string, sourceImage string) map[string]any {
	content := []map[string]any{
		{"text": strings.TrimSpace(prompt)},
	}
	if strings.TrimSpace(sourceImage) != "" {
		content = append(content, map[string]any{"image": strings.TrimSpace(sourceImage)})
	}
	return map[string]any{
		"model": strings.TrimSpace(model),
		"input": map[string]any{
			"messages": []map[string]any{
				{
					"role":    "user",
					"content": content,
				},
			},
		},
		"parameters": map[string]any{
			"prompt_extend":     true,
			"watermark":         false,
			"n":                 1,
			"enable_interleave": false,
			"size":              "1280*1280",
		},
	}
}

func parseGeneratedImageValue(respBody []byte) (string, error) {
	var resp struct {
		Data []struct {
			URL     string `json:"url"`
			B64JSON string `json:"b64_json"`
			Error   *struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		} `json:"data"`
		Error *struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
		Code    string `json:"code"`
		Message string `json:"message"`
		Output  struct {
			Image   string   `json:"image"`
			Images  []string `json:"images"`
			Results []struct {
				URL     string `json:"url"`
				Image   string `json:"image"`
				B64JSON string `json:"b64_json"`
			} `json:"results"`
			Choices []struct {
				Message struct {
					Content []struct {
						Image   string `json:"image"`
						URL     string `json:"url"`
						B64JSON string `json:"b64_json"`
					} `json:"content"`
				} `json:"message"`
			} `json:"choices"`
		} `json:"output"`
	}
	if err := json.Unmarshal(respBody, &resp); err != nil {
		return "", fmt.Errorf("parse image generation response failed: %w", err)
	}
	if resp.Error != nil {
		return "", fmt.Errorf("image generation failed: code=%s message=%s", strings.TrimSpace(resp.Error.Code), strings.TrimSpace(resp.Error.Message))
	}
	if code := strings.TrimSpace(resp.Code); code != "" && !strings.EqualFold(code, "200") && !strings.EqualFold(code, "ok") {
		return "", fmt.Errorf("image generation failed: code=%s message=%s", code, strings.TrimSpace(resp.Message))
	}
	for _, item := range resp.Output.Choices {
		for _, content := range item.Message.Content {
			if trimmed := strings.TrimSpace(content.B64JSON); trimmed != "" {
				return "data:image/png;base64," + trimmed, nil
			}
			if trimmed := strings.TrimSpace(content.Image); trimmed != "" {
				return trimmed, nil
			}
			if trimmed := strings.TrimSpace(content.URL); trimmed != "" {
				return trimmed, nil
			}
		}
	}
	for _, item := range resp.Output.Results {
		if trimmed := strings.TrimSpace(item.B64JSON); trimmed != "" {
			return "data:image/png;base64," + trimmed, nil
		}
		if trimmed := strings.TrimSpace(item.Image); trimmed != "" {
			return trimmed, nil
		}
		if trimmed := strings.TrimSpace(item.URL); trimmed != "" {
			return trimmed, nil
		}
	}
	if trimmed := strings.TrimSpace(resp.Output.Image); trimmed != "" {
		return trimmed, nil
	}
	for _, imageURL := range resp.Output.Images {
		if trimmed := strings.TrimSpace(imageURL); trimmed != "" {
			return trimmed, nil
		}
	}
	for _, item := range resp.Data {
		if trimmed := strings.TrimSpace(item.B64JSON); trimmed != "" {
			return "data:image/png;base64," + trimmed, nil
		}
		if strings.TrimSpace(item.URL) != "" {
			return strings.TrimSpace(item.URL), nil
		}
		if item.Error != nil {
			return "", fmt.Errorf("image generation failed: code=%s message=%s", strings.TrimSpace(item.Error.Code), strings.TrimSpace(item.Error.Message))
		}
	}
	return "", ErrInvalidResponse
}

func isInvalidImageParamError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "invalid url specified") ||
		strings.Contains(msg, "parameter `image`") ||
		strings.Contains(msg, "parameter \"image\"")
}

func normalizeSourceImageInputCandidates(sourceImage string) []string {
	trimmed := strings.TrimSpace(sourceImage)
	if trimmed == "" {
		return nil
	}
	lower := strings.ToLower(trimmed)
	if strings.HasPrefix(lower, "http://") ||
		strings.HasPrefix(lower, "https://") {
		return []string{trimmed}
	}
	if strings.HasPrefix(lower, "data:image/") {
		payload := extractDataURLBase64Payload(trimmed)
		if payload != "" {
			return []string{payload, trimmed}
		}
		return []string{trimmed}
	}
	return []string{trimmed, "data:image/jpeg;base64," + trimmed}
}

func extractDataURLBase64Payload(dataURL string) string {
	trimmed := strings.TrimSpace(dataURL)
	comma := strings.Index(trimmed, ",")
	if comma <= 0 || comma >= len(trimmed)-1 {
		return ""
	}
	header := strings.ToLower(trimmed[:comma])
	if !strings.HasPrefix(header, "data:image/") || !strings.Contains(header, ";base64") {
		return ""
	}
	return strings.TrimSpace(trimmed[comma+1:])
}

func (c *Client) GenerateCompanionReply(ctx context.Context, req CompanionReplyRequest) (CompanionReply, error) {
	ctx, cancel := context.WithTimeout(ctx, c.companionChatTimeout)
	defer cancel()

	historyBlock := buildCompanionHistoryBlock(req.History)
	promptSpec := renderCompanionPromptSpec(c.companionPromptSpec, req.ChildAge, req.ObjectType)

	body := map[string]any{
		"model": c.companionModel,
		"messages": []map[string]any{
			{
				"role":    "system",
				"content": buildCompanionReplySystemPromptWithSpec(promptSpec),
			},
			{
				"role":    "user",
				"content": buildCompanionReplyUserPromptWithSpec(req, historyBlock, promptSpec),
			},
		},
		"temperature": 0.7,
		"max_tokens":  180,
		"response_format": map[string]any{
			"type": "json_object",
		},
	}

	raw, err := c.doJSON(ctx, c.chatCompletionsPath, body)
	if err != nil {
		return CompanionReply{}, err
	}
	content, err := extractAssistantContent(raw)
	if err != nil {
		return CompanionReply{}, err
	}
	reply, err := parseCompanionReply(content)
	if err != nil {
		return CompanionReply{}, err
	}
	reply.RawContent = content
	return reply, nil
}

func (c *Client) SynthesizeSpeech(ctx context.Context, text string, objectType string) ([]byte, string, error) {
	if strings.TrimSpace(c.voiceAPIKey) == "" || strings.TrimSpace(c.voiceModelID) == "" {
		return nil, "", ErrVoiceCapabilityUnavailable
	}
	trimmedText := strings.TrimSpace(text)
	if trimmedText == "" {
		return nil, "", ErrInvalidResponse
	}

	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	requestURL := resolveTTSGenerationRequestURL(c.voiceBaseURL)
	for _, voice := range c.ttsVoiceCandidates(objectType, c.voiceID) {
		body := map[string]any{
			"model": strings.TrimSpace(c.voiceModelID),
			"input": map[string]any{
				"text":          trimmedText,
				"voice":         voice,
				"language_type": normalizeTTSLanguageType(c.voiceLangCode),
			},
			"parameters": map[string]any{
				"stream": false,
			},
		}
		respBody, _, err := c.doMediaJSON(ctx, requestURL, c.voiceAPIKey, body)
		if err != nil {
			if isInvalidTTSVoiceError(err) {
				continue
			}
			return nil, "", err
		}
		audioBytes, mimeType, err := c.parseDashScopeTTSAudio(ctx, respBody)
		if err != nil {
			if isInvalidTTSVoiceError(err) {
				continue
			}
			return nil, "", err
		}
		return audioBytes, mimeType, nil
	}
	return nil, "", fmt.Errorf("tts generation failed: no available voice for object_type=%s", strings.TrimSpace(objectType))
}

func resolveTTSGenerationRequestURL(baseURL string) string {
	trimmed := strings.TrimSpace(baseURL)
	if trimmed == "" {
		return "https://dashscope.aliyuncs.com" + dashScopeTTSGenerationPath
	}
	lower := strings.ToLower(trimmed)
	if strings.Contains(lower, "/api/v1/services/aigc/multimodal-generation/generation") {
		return strings.TrimRight(trimmed, "/")
	}
	return strings.TrimRight(trimmed, "/") + dashScopeTTSGenerationPath
}

func normalizeTTSLanguageType(lang string) string {
	switch strings.ToLower(strings.TrimSpace(lang)) {
	case "", "auto":
		return "Auto"
	case "zh", "cn", "zh-cn", "chinese":
		return "Chinese"
	case "en", "en-us", "english":
		return "English"
	case "ja", "japanese":
		return "Japanese"
	case "ko", "korean":
		return "Korean"
	case "fr", "french":
		return "French"
	case "de", "german":
		return "German"
	case "es", "spanish":
		return "Spanish"
	case "it", "italian":
		return "Italian"
	case "pt", "portuguese":
		return "Portuguese"
	case "ru", "russian":
		return "Russian"
	default:
		return strings.TrimSpace(lang)
	}
}

func (c *Client) ttsVoiceCandidates(objectType string, preferred string) []string {
	trimmedObjectType := strings.TrimSpace(objectType)
	pool := append([]string(nil), c.ttsFallbackVoices...)
	for _, profile := range c.ttsVoiceProfiles {
		if containsAny(trimmedObjectType, profile.Keywords...) {
			pool = append([]string(nil), profile.Voices...)
			break
		}
	}
	candidates := shuffleStrings(pool)
	if v := strings.TrimSpace(preferred); v != "" {
		candidates = append(candidates, v)
	}
	candidates = append(candidates, "Cherry")
	return uniqueNonEmptyStrings(candidates)
}

func containsAny(text string, keywords ...string) bool {
	lowerText := strings.ToLower(strings.TrimSpace(text))
	if lowerText == "" {
		return false
	}
	for _, keyword := range keywords {
		if strings.Contains(lowerText, strings.ToLower(strings.TrimSpace(keyword))) {
			return true
		}
	}
	return false
}

func shuffleStrings(items []string) []string {
	cloned := append([]string(nil), items...)
	if len(cloned) <= 1 {
		return cloned
	}
	r := rand.New(rand.NewSource(time.Now().UnixNano()))
	r.Shuffle(len(cloned), func(i, j int) {
		cloned[i], cloned[j] = cloned[j], cloned[i]
	})
	return cloned
}

func uniqueNonEmptyStrings(items []string) []string {
	result := make([]string, 0, len(items))
	seen := make(map[string]struct{}, len(items))
	for _, item := range items {
		trimmed := strings.TrimSpace(item)
		if trimmed == "" {
			continue
		}
		key := strings.ToLower(trimmed)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		result = append(result, trimmed)
	}
	return result
}

func isInvalidTTSVoiceError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "voice") &&
		(strings.Contains(msg, "invalid") ||
			strings.Contains(msg, "illegal") ||
			strings.Contains(msg, "not found"))
}

func (c *Client) parseDashScopeTTSAudio(ctx context.Context, respBody []byte) ([]byte, string, error) {
	var resp struct {
		StatusCode int    `json:"status_code"`
		RequestID  string `json:"request_id"`
		Code       string `json:"code"`
		Message    string `json:"message"`
		Output     struct {
			Audio struct {
				Data string `json:"data"`
				URL  string `json:"url"`
			} `json:"audio"`
		} `json:"output"`
	}
	if err := json.Unmarshal(respBody, &resp); err != nil {
		return nil, "", fmt.Errorf("parse tts response failed: %w", err)
	}
	if resp.StatusCode != 0 && resp.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("tts request failed: status_code=%d request_id=%s code=%s message=%s", resp.StatusCode, strings.TrimSpace(resp.RequestID), strings.TrimSpace(resp.Code), strings.TrimSpace(resp.Message))
	}
	if code := strings.TrimSpace(resp.Code); code != "" && !strings.EqualFold(code, "ok") && code != "200" {
		return nil, "", fmt.Errorf("tts request failed: request_id=%s code=%s message=%s", strings.TrimSpace(resp.RequestID), code, strings.TrimSpace(resp.Message))
	}
	if data := strings.TrimSpace(resp.Output.Audio.Data); data != "" {
		audio, err := base64.StdEncoding.DecodeString(data)
		if err != nil {
			return nil, "", fmt.Errorf("decode tts audio data failed: %w", err)
		}
		return audio, "audio/wav", nil
	}
	if audioURL := strings.TrimSpace(resp.Output.Audio.URL); audioURL != "" {
		return c.downloadBinary(ctx, audioURL, "audio/wav")
	}
	return nil, "", ErrInvalidResponse
}

func (c *Client) downloadBinary(ctx context.Context, resourceURL string, fallbackContentType string) ([]byte, string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimSpace(resourceURL), nil)
	if err != nil {
		return nil, "", err
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, "", fmt.Errorf("download resource failed, status=%d", resp.StatusCode)
	}
	contentType := strings.TrimSpace(resp.Header.Get("Content-Type"))
	if contentType == "" {
		contentType = fallbackContentType
	}
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	return body, contentType, nil
}

func (c *Client) DownloadImage(ctx context.Context, imageURL string) ([]byte, string, error) {
	trimmedURL := strings.TrimSpace(imageURL)
	if trimmedURL == "" {
		return nil, "", ErrInvalidResponse
	}
	if strings.HasPrefix(strings.ToLower(trimmedURL), "data:image/") {
		return decodeDataImageURL(trimmedURL)
	}

	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, trimmedURL, nil)
	if err != nil {
		return nil, "", err
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, "", err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, "", fmt.Errorf("download image failed, status=%d", resp.StatusCode)
	}
	contentType := strings.TrimSpace(resp.Header.Get("Content-Type"))
	if contentType == "" {
		contentType = "image/png"
	}
	return body, contentType, nil
}

func decodeDataImageURL(dataURL string) ([]byte, string, error) {
	comma := strings.Index(dataURL, ",")
	if comma <= 0 || comma >= len(dataURL)-1 {
		return nil, "", fmt.Errorf("invalid data url")
	}
	header := dataURL[:comma]
	payload := dataURL[comma+1:]
	if !strings.HasPrefix(strings.ToLower(header), "data:image/") {
		return nil, "", fmt.Errorf("unsupported data url")
	}
	if !strings.Contains(strings.ToLower(header), ";base64") {
		return nil, "", fmt.Errorf("data url is not base64 encoded")
	}
	mime := strings.TrimSpace(strings.TrimPrefix(strings.Split(header, ";")[0], "data:"))
	if mime == "" {
		mime = "image/png"
	}
	decoded, err := base64.StdEncoding.DecodeString(strings.TrimSpace(payload))
	if err != nil {
		return nil, "", err
	}
	return decoded, mime, nil
}

func (c *Client) doMediaJSON(ctx context.Context, requestURL string, apiKey string, payload any) ([]byte, http.Header, error) {
	respBody, headers, status, err := c.doMediaRequest(ctx, requestURL, apiKey, payload)
	if err != nil {
		return nil, nil, err
	}
	if status < 200 || status >= 300 {
		return nil, nil, fmt.Errorf("media request failed, status=%d body=%s", status, strings.TrimSpace(string(respBody)))
	}
	return respBody, headers, nil
}

func (c *Client) doMediaBinary(ctx context.Context, requestURL string, apiKey string, payload any) ([]byte, http.Header, error) {
	respBody, headers, status, err := c.doMediaRequest(ctx, requestURL, apiKey, payload)
	if err != nil {
		return nil, nil, err
	}
	if status < 200 || status >= 300 {
		return nil, nil, fmt.Errorf("media request failed, status=%d body=%s", status, strings.TrimSpace(string(respBody)))
	}
	return respBody, headers, nil
}

func (c *Client) doMediaRequest(ctx context.Context, requestURL string, apiKey string, payload any) ([]byte, http.Header, int, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, nil, 0, err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, requestURL, bytes.NewReader(body))
	if err != nil {
		return nil, nil, 0, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(apiKey))
	req.Header.Set("Content-Type", "application/json")
	if !isDashScopeImageRequestURL(requestURL) {
		req.Header.Set("x-app-id", c.appID)
		req.Header.Set("x-platform-id", c.platformID)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, nil, 0, err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, nil, resp.StatusCode, err
	}
	return respBody, resp.Header, resp.StatusCode, nil
}

func parseCompanionScene(content string) (CompanionScene, error) {
	payload := extractJSONPayload(strings.TrimSpace(content))
	var parsed struct {
		CharacterName string `json:"character_name"`
		Personality   string `json:"personality"`
		DialogText    string `json:"dialog_text"`
		ImagePrompt   string `json:"image_prompt"`
	}
	if err := unmarshalFirstJSONObject(payload, &parsed); err != nil {
		return CompanionScene{}, fmt.Errorf("parse companion scene failed: %w", err)
	}

	scene := CompanionScene{
		CharacterName:        strings.TrimSpace(parsed.CharacterName),
		CharacterPersonality: strings.TrimSpace(parsed.Personality),
		DialogText:           strings.TrimSpace(parsed.DialogText),
		ImagePrompt:          strings.TrimSpace(parsed.ImagePrompt),
	}
	if scene.CharacterName == "" || scene.DialogText == "" || scene.ImagePrompt == "" {
		return CompanionScene{}, ErrInvalidResponse
	}
	return scene, nil
}

func parseCompanionReply(content string) (CompanionReply, error) {
	payload := extractJSONPayload(strings.TrimSpace(content))
	var parsed struct {
		ReplyText string `json:"reply_text"`
	}
	if err := unmarshalFirstJSONObject(payload, &parsed); err != nil {
		return CompanionReply{}, fmt.Errorf("parse companion reply failed: %w", err)
	}
	reply := CompanionReply{
		ReplyText: strings.TrimSpace(parsed.ReplyText),
	}
	if reply.ReplyText == "" {
		return CompanionReply{}, ErrInvalidResponse
	}
	return reply, nil
}

func unmarshalFirstJSONObject(payload string, target any) error {
	decoder := json.NewDecoder(strings.NewReader(strings.TrimSpace(payload)))
	if err := decoder.Decode(target); err != nil {
		return err
	}
	return nil
}

func defaultText(v string, fallback string) string {
	v = strings.TrimSpace(v)
	if v == "" {
		return fallback
	}
	return v
}

func buildCompanionSceneSystemPrompt() string {
	return buildCompanionSceneSystemPromptWithSpec("")
}

func buildCompanionSceneSystemPromptWithSpec(promptSpec string) string {
	if strings.TrimSpace(promptSpec) != "" {
		return "你是儿童认知发展专家化身的“万物之灵”剧情伙伴。你必须完整遵循下方规则原文，不得删减、弱化或改写规则条款。只允许输出 JSON，不要 markdown，不要额外说明。\n\n[规则原文开始]\n" + promptSpec + "\n[规则原文结束]"
	}
	return "你是儿童认知发展专家化身的“万物之灵”剧情伙伴。只允许输出 JSON，不要 markdown，不要额外说明。"
}

func buildCompanionSceneUserPrompt(req CompanionSceneRequest) string {
	return buildCompanionSceneUserPromptWithSpec(req, "")
}

func buildCompanionSceneUserPromptWithSpec(req CompanionSceneRequest, promptSpec string) string {
	if strings.TrimSpace(promptSpec) != "" {
		age := normalizeCompanionAge(req.ChildAge)
		return fmt.Sprintf(
			`请严格遵循系统消息中的《prompt.txt 规则原文》生成剧情开场。
输入信息：
- 孩子年龄: %d
- 物体: %s
- 天气: %s
- 环境: %s
- 物体形态: %s
- 年龄认知层: %s

输出 JSON 字段（缺一不可）：
{"character_name":"", "personality":"", "dialog_text":"", "image_prompt":""}

补充约束（用于工程解析，不得违反规则原文）：
1) 只输出一个 JSON 对象，不要输出代码块。
2) dialog_text 必须是完整可朗读的简体中文台词。
3) 必须以“物体主体本体”第一人称叙述，禁止脱离物体身份扮演第三方角色（如“冒险家/老师/旁白”）。
4) character_name 必须与物体主体强相关（例如“狗狗”“路灯小灯灯”），不能是通用人设称呼。
5) dialog_text 第一段必须直接说“我是[该物体主体]”，不能只说抽象角色名。
6) image_prompt 必须是可直接用于生图的一段完整提示词。`,
			age,
			strings.TrimSpace(req.ObjectType),
			defaultText(req.Weather, "晴朗"),
			defaultText(req.Environment, "户外"),
			defaultText(req.ObjectTraits, "圆润可爱"),
			companionAgeLayerInstruction(age),
		)
	}

	age := normalizeCompanionAge(req.ChildAge)
	return fmt.Sprintf(
		`请基于以下输入生成剧情开场，并严格按 JSON 返回。
输入信息：
- 孩子年龄: %d
- 物体: %s
- 天气: %s
- 环境: %s
- 物体形态: %s
- 年龄认知层: %s

输出 JSON 字段（缺一不可）：
{"character_name":"", "personality":"", "dialog_text":"", "image_prompt":""}

写作规则（必须满足）：
1) dialog_text 必须用第一人称“我”，并且第一句直接说明“我是谁”（例如“你好呀，我是……”）；第一句必须同时包含1个情绪词（如：开心/惊喜/好奇/兴奋）和1个状态词（如：正在/现在正/刚刚/今天正）。
2) 先做危险扫描：触电/烫伤/割伤/有毒/夹伤/坠落/动物攻击/过敏。若有风险，在开场后单独一段以“⚠️”开头预警；若无风险，不要输出预警。
3) dialog_text 采用“观察细节 -> 小秘密科普 -> 身体互动 -> 只问一个问题 -> 邀请孩子继续提问”的节奏。
4) 全文只能有一个问句，且语言要符合该年龄层认知与口语习惯，适合语音朗读。
5) 比喻必须忠于事实，禁止编造危险结论或夸大能力。
6) dialog_text 结尾固定追加：“你还有什么想知道的吗？随便问——我在这儿听着呢！”
7) 使用简体中文，不要使用编号、标签词（如Step 1）或Markdown。

image_prompt 规则（必须满足）：
1) 童话儿童绘本风，柔和光线，适合作为剧情对话背景。
2) 主体拟人化但保持原物体关键特征，主体视线看向镜头（看向屏幕中的小朋友）。
3) 主体可视面积约占画面1/5，位置居中或微偏中景，构图有前中后景层次。
4) 场景必须符合主体在现实生活中的常见出现环境。
5) 禁止文字、水印、logo。`,
		age,
		strings.TrimSpace(req.ObjectType),
		defaultText(req.Weather, "晴朗"),
		defaultText(req.Environment, "户外"),
		defaultText(req.ObjectTraits, "圆润可爱"),
		companionAgeLayerInstruction(age),
	)
}

func buildCompanionReplySystemPrompt() string {
	return buildCompanionReplySystemPromptWithSpec("")
}

func buildCompanionReplySystemPromptWithSpec(promptSpec string) string {
	if strings.TrimSpace(promptSpec) != "" {
		return "你是儿童剧情互动角色，持续用第一人称“我”与孩子多轮对话。你必须完整遵循下方规则原文，不得删减、弱化或改写规则条款。只输出 JSON，不要 markdown。\n\n[规则原文开始]\n" + promptSpec + "\n[规则原文结束]"
	}
	return "你是儿童剧情互动角色，持续用第一人称“我”与孩子多轮对话。只输出 JSON，不要 markdown。"
}

func buildCompanionHistoryBlock(history []string) string {
	if len(history) == 0 {
		return "(无历史对话)"
	}
	filtered := make([]string, 0, len(history))
	for _, entry := range history {
		line := strings.TrimSpace(entry)
		if line == "" {
			continue
		}
		filtered = append(filtered, line)
	}
	if len(filtered) == 0 {
		return "(无历史对话)"
	}
	if len(filtered) > companionHistoryLimit {
		filtered = filtered[len(filtered)-companionHistoryLimit:]
	}
	return strings.Join(filtered, "\n")
}

func buildCompanionReplyUserPrompt(req CompanionReplyRequest, historyBlock string) string {
	return buildCompanionReplyUserPromptWithSpec(req, historyBlock, "")
}

func buildCompanionReplyUserPromptWithSpec(req CompanionReplyRequest, historyBlock string, promptSpec string) string {
	if strings.TrimSpace(promptSpec) != "" {
		age := normalizeCompanionAge(req.ChildAge)
		return fmt.Sprintf(
			`请严格遵循系统消息中的《prompt.txt 规则原文》，并延续角色设定继续回复。
输入信息：
- 孩子年龄: %d
- 物体: %s
- 角色名: %s
- 角色性格: %s
- 天气: %s
- 环境: %s
- 物体形态: %s
- 年龄认知层: %s
- 历史对话:
%s
- 孩子最新输入: %s

输出 JSON 字段：
{"reply_text":""}

补充约束（用于工程解析，不得违反规则原文）：
1) 只输出一个 JSON 对象，不要输出代码块。
2) reply_text 必须与历史上下文一致，并先回应孩子最新输入。
3) reply_text 必须保持物体主体第一人称，不允许切换成第三方旁白或人类导师视角。`,
			age,
			strings.TrimSpace(req.ObjectType),
			defaultText(req.CharacterName, "城市小精灵"),
			defaultText(req.CharacterPersonality, "友好"),
			defaultText(req.Weather, "晴朗"),
			defaultText(req.Environment, "户外"),
			defaultText(req.ObjectTraits, "可爱"),
			companionAgeLayerInstruction(age),
			historyBlock,
			strings.TrimSpace(req.ChildMessage),
		)
	}

	age := normalizeCompanionAge(req.ChildAge)
	return fmt.Sprintf(
		`请延续角色设定继续回复，严格按 JSON 输出。
输入信息：
- 孩子年龄: %d
- 物体: %s
- 角色名: %s
- 角色性格: %s
- 天气: %s
- 环境: %s
- 物体形态: %s
- 年龄认知层: %s
- 历史对话:
%s
- 孩子最新输入: %s

输出 JSON 字段：
{"reply_text":""}

回复规则（必须满足）：
1) 只输出角色台词，第一人称口吻，简体中文；首句优先包含情绪词和状态词，增强陪伴感。
2) 先回应孩子刚刚的话，再引导观察或思考。
3) 一次只问一个问题；如果当前回复不需要提问，可以不问。
4) 语气鼓励、自然、可朗读，不要说教，不要罗列编号。
5) 保持与历史设定一致，不重复机械套话。`,
		age,
		strings.TrimSpace(req.ObjectType),
		defaultText(req.CharacterName, "城市小精灵"),
		defaultText(req.CharacterPersonality, "友好"),
		defaultText(req.Weather, "晴朗"),
		defaultText(req.Environment, "户外"),
		defaultText(req.ObjectTraits, "可爱"),
		companionAgeLayerInstruction(age),
		historyBlock,
		strings.TrimSpace(req.ChildMessage),
	)
}

func normalizeCompanionAge(age int) int {
	if age < 3 {
		return 3
	}
	if age > 15 {
		return 15
	}
	return age
}

func companionAgeLayerInstruction(age int) string {
	switch {
	case age <= 6:
		return "3-6岁：短句、具象、像生活故事一样描述。"
	case age <= 12:
		return "7-12岁：强调因果与结构，口语化解释“为什么”。"
	default:
		return "13-15岁：可加入系统思维、成本与权衡，但保持易懂。"
	}
}
