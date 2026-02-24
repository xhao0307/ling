package llm

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
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

func (c *Client) GenerateCompanionScene(ctx context.Context, req CompanionSceneRequest) (CompanionScene, error) {
	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	body := map[string]any{
		"gpt_type": c.textGPTType,
		"messages": []map[string]any{
			{
				"role":    "system",
				"content": "你是儿童剧情互动编剧。仅输出 JSON，不要 markdown。",
			},
			{
				"role": "user",
				"content": fmt.Sprintf(
					"孩子年龄:%d\n物体:%s\n天气:%s\n环境:%s\n物体形态:%s\n请输出 JSON 字段：character_name, personality, dialog_text, image_prompt。要求：1) 角色为拟人卡通形象，适合儿童；2) dialog_text 1-2 句，口吻友好；3) image_prompt 用于文生图，描述卡通角色、场景与光线，中文。",
					req.ChildAge,
					strings.TrimSpace(req.ObjectType),
					defaultText(req.Weather, "晴朗"),
					defaultText(req.Environment, "户外"),
					defaultText(req.ObjectTraits, "圆润可爱"),
				),
			},
		},
		"temperature": 0.8,
		"max_tokens":  600,
		"response_format": map[string]any{
			"type": "json_object",
		},
	}

	raw, err := c.doJSON(ctx, "/v1/chat/completions", body)
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

func (c *Client) GenerateCharacterImage(ctx context.Context, imagePrompt string) (string, error) {
	if strings.TrimSpace(c.imageAPIKey) == "" {
		return "", ErrImageCapabilityUnavailable
	}

	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	body := map[string]any{
		"model":           c.imageModel,
		"prompt":          strings.TrimSpace(imagePrompt),
		"n":               1,
		"response_format": "url",
		"size":            "2K",
		"stream":          false,
		"watermark":       true,
	}
	respBody, _, err := c.doMediaJSON(ctx, c.imageBaseURL+"/v1/byteplus/images/generations", c.imageAPIKey, body)
	if err != nil {
		return "", err
	}

	var resp struct {
		Data []struct {
			URL   string `json:"url"`
			Error *struct {
				Code    string `json:"code"`
				Message string `json:"message"`
			} `json:"error"`
		} `json:"data"`
		Error *struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(respBody, &resp); err != nil {
		return "", fmt.Errorf("parse image generation response failed: %w", err)
	}
	if resp.Error != nil {
		return "", fmt.Errorf("image generation failed: code=%s message=%s", strings.TrimSpace(resp.Error.Code), strings.TrimSpace(resp.Error.Message))
	}
	for _, item := range resp.Data {
		if strings.TrimSpace(item.URL) != "" {
			return strings.TrimSpace(item.URL), nil
		}
		if item.Error != nil {
			return "", fmt.Errorf("image generation failed: code=%s message=%s", strings.TrimSpace(item.Error.Code), strings.TrimSpace(item.Error.Message))
		}
	}
	return "", ErrInvalidResponse
}

func (c *Client) SynthesizeSpeech(ctx context.Context, text string) ([]byte, string, error) {
	if strings.TrimSpace(c.voiceAPIKey) == "" || strings.TrimSpace(c.voiceID) == "" {
		return nil, "", ErrVoiceCapabilityUnavailable
	}

	ctx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	body := map[string]any{
		"text":          strings.TrimSpace(text),
		"voice_id":      c.voiceID,
		"model_id":      c.voiceModelID,
		"language_code": c.voiceLangCode,
		"voice_settings": map[string]any{
			"stability":        0.45,
			"similarity_boost": 0.75,
			"speed":            1.0,
		},
	}

	requestURL := c.voiceBaseURL + "/elevenlabs/tts/generate?output_format=" + url.QueryEscape(c.voiceFormat)
	audio, headers, err := c.doMediaBinary(ctx, requestURL, c.voiceAPIKey, body)
	if err != nil {
		return nil, "", err
	}
	contentType := strings.TrimSpace(headers.Get("Content-Type"))
	if contentType == "" {
		contentType = "audio/mpeg"
	}
	return audio, contentType, nil
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
	req.Header.Set("x-app-id", c.appID)
	req.Header.Set("x-platform-id", c.platformID)

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
	if err := json.Unmarshal([]byte(payload), &parsed); err != nil {
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

func defaultText(v string, fallback string) string {
	v = strings.TrimSpace(v)
	if v == "" {
		return fallback
	}
	return v
}
