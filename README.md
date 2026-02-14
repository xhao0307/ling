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
- `CITYLING_LLM_API_KEY` (enable LLM integration when set)
- `CITYLING_LLM_BASE_URL` (default `https://api-chat.charaboard.com`)
- `CITYLING_LLM_APP_ID` (default `4`)
- `CITYLING_LLM_PLATFORM_ID` (default `5`)
- `CITYLING_LLM_VISION_GPT_TYPE` (default `8102`, V2 multimodal recognition)
- `CITYLING_LLM_TEXT_GPT_TYPE` (default `8602`, V1 text generation)
- `CITYLING_LLM_TIMEOUT_SECONDS` (default `20`)

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
    "image_base64":"<base64>"
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
flutter run --dart-define=CITYLING_BASE_URL=http://10.0.2.2:8080
```
