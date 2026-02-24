package httpapi

import (
	"net/http"
	"strings"
)

func (h *Handler) swaggerUI(w http.ResponseWriter, r *http.Request) {
	const page = `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>City Ling API Swagger</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css" />
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    const docPath = window.location.pathname.startsWith('/swagger')
      ? '/swagger/openapi.json'
      : '/docs/openapi.json';
    window.ui = SwaggerUIBundle({
      url: docPath,
      dom_id: '#swagger-ui'
    });
  </script>
</body>
</html>`
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = w.Write([]byte(page))
}

func (h *Handler) swaggerSpec(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, openAPISpec(requestBaseURL(r)))
}

func requestBaseURL(r *http.Request) string {
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	if forwarded := strings.TrimSpace(r.Header.Get("X-Forwarded-Proto")); forwarded != "" {
		scheme = strings.Split(forwarded, ",")[0]
		scheme = strings.TrimSpace(scheme)
	}

	host := strings.TrimSpace(r.Host)
	if host == "" {
		host = "localhost:8080"
	}
	return scheme + "://" + host
}

func openAPISpec(serverURL string) map[string]any {
	return map[string]any{
		"openapi": "3.0.3",
		"info": map[string]any{
			"title":       "City Ling API",
			"description": "城市灵后端 API 文档",
			"version":     "1.0.0",
		},
		"servers": []map[string]string{
			{"url": serverURL},
		},
		"paths": map[string]any{
			"/healthz": map[string]any{
				"get": map[string]any{
					"summary":     "健康检查",
					"operationId": "healthz",
					"responses": map[string]any{
						"200": map[string]any{
							"description": "OK",
							"content": map[string]any{
								"application/json": map[string]any{
									"schema": map[string]any{"$ref": "#/components/schemas/HealthResponse"},
								},
							},
						},
					},
				},
			},
			"/api/v1/scan": map[string]any{
				"post": map[string]any{
					"summary":     "根据图片或标签生成题目和科普",
					"operationId": "scan",
					"requestBody": map[string]any{
						"required": true,
						"content": map[string]any{
							"application/json": map[string]any{
								"schema": map[string]any{"$ref": "#/components/schemas/ScanRequest"},
							},
						},
					},
					"responses": map[string]any{
						"200": map[string]any{
							"description": "成功",
							"content": map[string]any{
								"application/json": map[string]any{
									"schema": map[string]any{"$ref": "#/components/schemas/ScanResponse"},
								},
							},
						},
						"400": map[string]any{"description": "请求错误"},
						"503": map[string]any{"description": "未配置大模型能力（图片识别场景）"},
						"500": map[string]any{"description": "服务错误"},
					},
				},
			},
			"/api/v1/scan/image": map[string]any{
				"post": map[string]any{
					"summary":     "上传图片并由大模型识别主体",
					"operationId": "scanImage",
					"requestBody": map[string]any{
						"required": true,
						"content": map[string]any{
							"application/json": map[string]any{
								"schema": map[string]any{"$ref": "#/components/schemas/ScanImageRequest"},
							},
						},
					},
					"responses": map[string]any{
						"200": map[string]any{
							"description": "成功",
							"content": map[string]any{
								"application/json": map[string]any{
									"schema": map[string]any{"$ref": "#/components/schemas/ScanImageResponse"},
								},
							},
						},
						"400": map[string]any{"description": "请求错误"},
						"503": map[string]any{"description": "未配置大模型能力"},
						"500": map[string]any{"description": "服务错误"},
					},
				},
			},
			"/api/v1/companion/scene": map[string]any{
				"post": map[string]any{
					"summary":     "生成角色剧情首句、卡通图与语音",
					"operationId": "companionScene",
					"requestBody": map[string]any{
						"required": true,
						"content": map[string]any{
							"application/json": map[string]any{
								"schema": map[string]any{"$ref": "#/components/schemas/CompanionSceneRequest"},
							},
						},
					},
					"responses": map[string]any{
						"200": map[string]any{
							"description": "成功",
							"content": map[string]any{
								"application/json": map[string]any{
									"schema": map[string]any{"$ref": "#/components/schemas/CompanionSceneResponse"},
								},
							},
						},
						"400": map[string]any{"description": "请求错误"},
						"503": map[string]any{"description": "未配置大模型/生图/TTS能力"},
						"500": map[string]any{"description": "服务错误"},
					},
				},
			},
			"/api/v1/companion/chat": map[string]any{
				"post": map[string]any{
					"summary":     "角色剧情多轮对话（文本+语音）",
					"operationId": "companionChat",
					"requestBody": map[string]any{
						"required": true,
						"content": map[string]any{
							"application/json": map[string]any{
								"schema": map[string]any{"$ref": "#/components/schemas/CompanionChatRequest"},
							},
						},
					},
					"responses": map[string]any{
						"200": map[string]any{
							"description": "成功",
							"content": map[string]any{
								"application/json": map[string]any{
									"schema": map[string]any{"$ref": "#/components/schemas/CompanionChatResponse"},
								},
							},
						},
						"400": map[string]any{"description": "请求错误"},
						"503": map[string]any{"description": "未配置大模型/TTS能力"},
						"500": map[string]any{"description": "服务错误"},
					},
				},
			},
			"/api/v1/answer": map[string]any{
				"post": map[string]any{
					"summary":     "提交答案",
					"operationId": "answer",
					"requestBody": map[string]any{
						"required": true,
						"content": map[string]any{
							"application/json": map[string]any{
								"schema": map[string]any{"$ref": "#/components/schemas/AnswerRequest"},
							},
						},
					},
					"responses": map[string]any{
						"200": map[string]any{
							"description": "成功",
							"content": map[string]any{
								"application/json": map[string]any{
									"schema": map[string]any{"$ref": "#/components/schemas/AnswerResponse"},
								},
							},
						},
						"404": map[string]any{"description": "会话不存在"},
						"409": map[string]any{"description": "会话已完成"},
						"500": map[string]any{"description": "服务错误"},
					},
				},
			},
			"/api/v1/pokedex": map[string]any{
				"get": map[string]any{
					"summary":     "查询图鉴",
					"operationId": "pokedex",
					"parameters": []map[string]any{
						{
							"name":        "child_id",
							"in":          "query",
							"required":    false,
							"description": "孩子 ID，默认 guest",
							"schema":      map[string]any{"type": "string"},
						},
					},
					"responses": map[string]any{
						"200": map[string]any{
							"description": "成功",
							"content": map[string]any{
								"application/json": map[string]any{
									"schema": map[string]any{"$ref": "#/components/schemas/PokedexResponse"},
								},
							},
						},
					},
				},
			},
			"/api/v1/report/daily": map[string]any{
				"get": map[string]any{
					"summary":     "查询每日报告",
					"operationId": "dailyReport",
					"parameters": []map[string]any{
						{
							"name":        "child_id",
							"in":          "query",
							"required":    false,
							"description": "孩子 ID，默认 guest",
							"schema":      map[string]any{"type": "string"},
						},
						{
							"name":        "date",
							"in":          "query",
							"required":    false,
							"description": "日期，格式 YYYY-MM-DD",
							"schema":      map[string]any{"type": "string"},
						},
					},
					"responses": map[string]any{
						"200": map[string]any{
							"description": "成功",
							"content": map[string]any{
								"application/json": map[string]any{
									"schema": map[string]any{"$ref": "#/components/schemas/DailyReport"},
								},
							},
						},
						"400": map[string]any{"description": "日期格式错误"},
						"500": map[string]any{"description": "服务错误"},
					},
				},
			},
		},
		"components": map[string]any{
			"schemas": map[string]any{
				"HealthResponse": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"status": map[string]any{"type": "string", "example": "ok"},
					},
				},
				"ErrorResponse": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"error": map[string]any{"type": "string"},
					},
				},
				"ScanRequest": map[string]any{
					"type":        "object",
					"required":    []string{"child_id", "child_age"},
					"description": "支持两种模式：1) 传 detected_label；2) 传 image_url 或 image_base64（自动识别后再出题）。",
					"properties": map[string]any{
						"child_id":       map[string]any{"type": "string"},
						"child_age":      map[string]any{"type": "integer"},
						"detected_label": map[string]any{"type": "string"},
						"image_base64":   map[string]any{"type": "string"},
						"image_url":      map[string]any{"type": "string"},
					},
				},
				"ScanImageRequest": map[string]any{
					"type":     "object",
					"required": []string{"child_id", "child_age"},
					"properties": map[string]any{
						"child_id":     map[string]any{"type": "string"},
						"child_age":    map[string]any{"type": "integer"},
						"image_base64": map[string]any{"type": "string"},
						"image_url":    map[string]any{"type": "string"},
					},
				},
				"AnswerRequest": map[string]any{
					"type":     "object",
					"required": []string{"session_id", "child_id", "answer"},
					"properties": map[string]any{
						"session_id": map[string]any{"type": "string"},
						"child_id":   map[string]any{"type": "string"},
						"answer":     map[string]any{"type": "string"},
					},
				},
				"CompanionSceneRequest": map[string]any{
					"type":     "object",
					"required": []string{"child_age", "object_type"},
					"properties": map[string]any{
						"child_id":            map[string]any{"type": "string"},
						"child_age":           map[string]any{"type": "integer"},
						"object_type":         map[string]any{"type": "string"},
						"weather":             map[string]any{"type": "string"},
						"environment":         map[string]any{"type": "string"},
						"object_traits":       map[string]any{"type": "string"},
						"source_image_base64": map[string]any{"type": "string", "description": "可选。传入识别原图，启用图生图角色生成"},
					},
				},
				"CompanionChatRequest": map[string]any{
					"type":     "object",
					"required": []string{"child_age", "object_type", "child_message"},
					"properties": map[string]any{
						"child_id":              map[string]any{"type": "string"},
						"child_age":             map[string]any{"type": "integer"},
						"object_type":           map[string]any{"type": "string"},
						"character_name":        map[string]any{"type": "string"},
						"character_personality": map[string]any{"type": "string"},
						"weather":               map[string]any{"type": "string"},
						"environment":           map[string]any{"type": "string"},
						"object_traits":         map[string]any{"type": "string"},
						"history": map[string]any{
							"type":  "array",
							"items": map[string]any{"type": "string"},
						},
						"child_message": map[string]any{"type": "string"},
					},
				},
				"Spirit": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"id":          map[string]any{"type": "string"},
						"name":        map[string]any{"type": "string"},
						"object_type": map[string]any{"type": "string"},
						"personality": map[string]any{"type": "string"},
						"intro":       map[string]any{"type": "string"},
						"created_at":  map[string]any{"type": "string", "format": "date-time"},
					},
				},
				"ScanResponse": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"session_id":  map[string]any{"type": "string"},
						"object_type": map[string]any{"type": "string"},
						"spirit":      map[string]any{"$ref": "#/components/schemas/Spirit"},
						"fact":        map[string]any{"type": "string"},
						"quiz":        map[string]any{"type": "string"},
						"dialogues": map[string]any{
							"type":  "array",
							"items": map[string]any{"type": "string"},
						},
						"cache_hit": map[string]any{"type": "boolean"},
					},
				},
				"ScanImageResponse": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"detected_label":    map[string]any{"type": "string", "description": "中文识别结果"},
						"detected_label_en": map[string]any{"type": "string", "description": "英文标准标签(mailbox/tree/manhole/road_sign/traffic_light)"},
						"raw_label":         map[string]any{"type": "string"},
						"reason":            map[string]any{"type": "string"},
					},
				},
				"CompanionSceneResponse": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"character_name":        map[string]any{"type": "string"},
						"character_personality": map[string]any{"type": "string"},
						"dialog_text":           map[string]any{"type": "string"},
						"image_prompt":          map[string]any{"type": "string"},
						"character_image_url":   map[string]any{"type": "string"},
						"character_image_base64": map[string]any{
							"type":        "string",
							"description": "可选。角色图的base64数据，前端可优先使用以避免外链加载失败",
						},
						"character_image_mime_type": map[string]any{"type": "string"},
						"voice_audio_base64":        map[string]any{"type": "string"},
						"voice_mime_type":           map[string]any{"type": "string"},
					},
				},
				"CompanionChatResponse": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"reply_text":         map[string]any{"type": "string"},
						"voice_audio_base64": map[string]any{"type": "string"},
						"voice_mime_type":    map[string]any{"type": "string"},
					},
				},
				"Capture": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"id":          map[string]any{"type": "string"},
						"child_id":    map[string]any{"type": "string"},
						"spirit_id":   map[string]any{"type": "string"},
						"spirit_name": map[string]any{"type": "string"},
						"object_type": map[string]any{"type": "string"},
						"fact":        map[string]any{"type": "string"},
						"captured_at": map[string]any{"type": "string", "format": "date-time"},
					},
				},
				"AnswerResponse": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"correct":  map[string]any{"type": "boolean"},
						"captured": map[string]any{"type": "boolean"},
						"message":  map[string]any{"type": "string"},
						"capture":  map[string]any{"$ref": "#/components/schemas/Capture"},
					},
				},
				"PokedexEntry": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"spirit_id":   map[string]any{"type": "string"},
						"spirit_name": map[string]any{"type": "string"},
						"object_type": map[string]any{"type": "string"},
						"captures":    map[string]any{"type": "integer"},
						"last_seen_at": map[string]any{
							"type":   "string",
							"format": "date-time",
						},
					},
				},
				"PokedexResponse": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"child_id": map[string]any{"type": "string"},
						"entries": map[string]any{
							"type":  "array",
							"items": map[string]any{"$ref": "#/components/schemas/PokedexEntry"},
						},
					},
				},
				"DailyReport": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"date":           map[string]any{"type": "string"},
						"child_id":       map[string]any{"type": "string"},
						"total_captured": map[string]any{"type": "integer"},
						"captures": map[string]any{
							"type":  "array",
							"items": map[string]any{"$ref": "#/components/schemas/Capture"},
						},
						"knowledge_points": map[string]any{
							"type":  "array",
							"items": map[string]any{"type": "string"},
						},
						"generated_text": map[string]any{"type": "string"},
						"generated_at":   map[string]any{"type": "string", "format": "date-time"},
					},
				},
			},
		},
	}
}
