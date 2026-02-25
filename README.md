# City Ling MVP Backend

This is the first runnable backend implementation for the "City Ling" product plan.

Implemented MVP loop:
- scan object label (or image-based recognition)
- generate a spirit, dialogues, and quiz
- answer quiz to capture spirit
- browse pokedex
- generate daily report

## Run

```bash
go run ./cmd/server
```

Config file:
- Preferred: `ling.ini` in project root (format: `KEY=VALUE`)
- Backward compatible: `.env`

Specify host and port at startup:

```bash
go run ./cmd/server -host 0.0.0.0 -port 8080
```

Optional environment variables:
- `CITYLING_ADDR` (default `:8080`)
- `CITYLING_HOST` (optional, e.g. `0.0.0.0`)
- `CITYLING_PORT` (optional, e.g. `8080`)
- `CITYLING_STORE` (`sqlite` or `json`, default `sqlite`)
- `CITYLING_DATA_FILE` (default `data/cityling.db` for sqlite, `data/cityling.json` for json)
- `CITYLING_DASHSCOPE_API_KEY` (用于文本/视觉大模型，enable LLM integration when set)
- 聊天识别链路固定使用 `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`
- 聊天识别模型固定使用 `qwen3.5-flash`
- `CITYLING_LLM_APP_ID` (default `4`)
- `CITYLING_LLM_PLATFORM_ID` (default `5`)
- `CITYLING_LLM_TIMEOUT_SECONDS` (default `20`)
- `CITYLING_IMAGE_API_BASE_URL` (default `https://api-image.charaboard.com`)
- `CITYLING_IMAGE_API_KEY` (optional, fallback to `CITYLING_DASHSCOPE_API_KEY`)
- `CITYLING_IMAGE_MODEL` (default `seedream-4-0-250828`)
- `CITYLING_IMAGE_RESPONSE_FORMAT` (`b64_json` or `url`, default `b64_json`)
- `CITYLING_TTS_API_BASE_URL` (default `https://api-voice.charaboard.com`)
- `CITYLING_LLM_API_KEY` (用于文字转语音默认 key，保持原有链路)
- `CITYLING_TTS_API_KEY` (optional, fallback to `CITYLING_LLM_API_KEY`)
- `CITYLING_TTS_VOICE_ID` (default `Xb7hH8MSUJpSbSDYk0k2`)
- `CITYLING_TTS_MODEL_ID` (default `eleven_multilingual_v2`)
- `CITYLING_TTS_LANGUAGE_CODE` (default `zh`)
- `CITYLING_TTS_OUTPUT_FORMAT` (default `mp3_44100_128`)

## API

### Health

```bash
curl -s http://localhost:8080/healthz
```

### Swagger / OpenAPI

- Swagger UI: `http://localhost:8080/docs`
- OpenAPI JSON: `http://localhost:8080/docs/openapi.json`
- Backward-compatible aliases: `/swagger` and `/swagger/openapi.json`

### Scan (label or image)

```bash
curl -s -X POST http://localhost:8080/api/v1/scan \
  -H "Content-Type: application/json" \
  -d '{
    "child_id":"kid_1",
    "child_age":8,
    "detected_label":"mailbox"
  }'
```

Image mode (auto-recognize then generate):

```bash
curl -s -X POST http://localhost:8080/api/v1/scan \
  -H "Content-Type: application/json" \
  -d '{
    "child_id":"kid_1",
    "child_age":8,
    "image_url":"https://example.com/road.jpg"
  }'
```

### Scan image (LLM multimodal)

```bash
curl -s -X POST http://localhost:8080/api/v1/scan/image \
  -H "Content-Type: application/json" \
  -d '{
    "child_id":"kid_1",
    "child_age":8,
    "image_url":"https://example.com/cat.jpg"
  }'
```

### Upload image (返回公网 URL，前端推荐先调用)

```bash
curl -s -X POST http://localhost:8080/api/v1/media/upload \
  -F "file=@./cat.png"
```

### Companion scene (角色剧情图像+语音)

```bash
curl -s -X POST http://localhost:8080/api/v1/companion/scene \
  -H "Content-Type: application/json" \
  -d '{
    "child_id":"kid_1",
    "child_age":8,
    "object_type":"路灯",
    "weather":"雨后",
    "environment":"小区花园",
    "object_traits":"细长金属杆，顶部发暖光",
    "source_image_url":"https://example.com/cat.jpg"
  }'
```

### Companion chat (多轮剧情对话+语音)

```bash
curl -s -X POST http://localhost:8080/api/v1/companion/chat \
  -H "Content-Type: application/json" \
  -d '{
    "child_id":"kid_1",
    "child_age":8,
    "object_type":"路灯",
    "character_name":"云朵灯灯",
    "character_personality":"温柔好奇",
    "weather":"雨后",
    "environment":"小区花园",
    "object_traits":"细长金属杆，顶部发暖光",
    "history":["角色：你好呀，我们一起观察路灯吧。","孩子：为什么它会亮？"],
    "child_message":"我觉得是电让它亮起来的"
  }'
```

### Submit answer

```bash
curl -s -X POST http://localhost:8080/api/v1/answer \
  -H "Content-Type: application/json" \
  -d '{
    "session_id":"sess_xxx",
    "child_id":"kid_1",
    "answer":"letters"
  }'
```

### Pokedex

```bash
curl -s "http://localhost:8080/api/v1/pokedex?child_id=kid_1"
```

### Daily report

```bash
curl -s "http://localhost:8080/api/v1/report/daily?child_id=kid_1&date=2026-02-13"
```

## Notes

- Image recognition uses LLM multimodal API when configured.
- Quiz/fact/dialogues generation uses LLM text API when configured, and automatically falls back to local knowledge on timeout/failure.
- Flutter client includes full-screen camera mode and sends snapshots to backend for recognition.
- Persistence supports local SQLite (default) and JSON.
- Replaceable seams are already in place:
  - image recognizer provider
  - storage layer
  - report text generation

## Flutter Client

A Flutter client shell is included in `flutter_client/`.

Quick start after installing Flutter:

```bash
cd flutter_client
flutter create .
flutter pub get
flutter run --dart-define=CITYLING_BASE_URL=http://121.43.118.53:3026
```
