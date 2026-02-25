package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"ling/internal/httpapi"
	"ling/internal/knowledge"
	"ling/internal/llm"
	"ling/internal/service"
	"ling/internal/store"
)

func main() {
	if err := loadConfigFile("ling.ini"); err != nil {
		log.Printf("load ling.ini failed: %v", err)
	}
	// Backward compatibility: still accept .env when present.
	if err := loadConfigFile(".env"); err != nil {
		log.Printf("load .env failed: %v", err)
	}

	addr := resolveListenAddr()
	storeEngine := strings.ToLower(envOrDefault("CITYLING_STORE", store.EngineSQLite))
	dataFile := envOrDefault("CITYLING_DATA_FILE", defaultDataFile(storeEngine))

	st, err := store.NewByEngine(storeEngine, dataFile)
	if err != nil {
		log.Fatalf("init store failed: %v", err)
	}
	if closer, ok := st.(io.Closer); ok {
		defer func() {
			if err := closer.Close(); err != nil {
				log.Printf("store close failed: %v", err)
			}
		}()
	}

	svc := service.New(st, knowledge.BaseKnowledge)
	if llmClient := initLLMClientFromEnv(); llmClient != nil {
		svc.SetLLMClient(llmClient)
		log.Printf("llm integration enabled")
	} else {
		log.Printf("llm integration disabled, using local knowledge fallback only")
	}
	handler := httpapi.NewHandler(svc)
	router := httpapi.NewRouter(handler)

	server := &http.Server{
		Addr:              addr,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("city ling backend listening on %s", addr)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("server failed: %v", err)
	}
}

func resolveListenAddr() string {
	defaultHost, defaultPort := parseListenAddr(envOrDefault("CITYLING_ADDR", ":8080"))
	if defaultPort <= 0 {
		defaultPort = 8080
	}

	defaultHost = strings.TrimSpace(envOrDefault("CITYLING_HOST", defaultHost))
	defaultPort = parseEnvInt("CITYLING_PORT", defaultPort)

	host := flag.String("host", defaultHost, "server listen host, e.g. 0.0.0.0")
	port := flag.Int("port", defaultPort, "server listen port, e.g. 8080")
	flag.Parse()

	return joinListenAddr(strings.TrimSpace(*host), *port)
}

func parseListenAddr(addr string) (string, int) {
	addr = strings.TrimSpace(addr)
	if addr == "" {
		return "", 0
	}
	if strings.HasPrefix(addr, ":") {
		return "", parseEnvIntValue(strings.TrimPrefix(addr, ":"), 0)
	}
	if host, port, err := net.SplitHostPort(addr); err == nil {
		return host, parseEnvIntValue(port, 0)
	}
	if portOnly := parseEnvIntValue(addr, 0); portOnly > 0 {
		return "", portOnly
	}
	return addr, 0
}

func joinListenAddr(host string, port int) string {
	if port <= 0 {
		port = 8080
	}
	if host == "" {
		return fmt.Sprintf(":%d", port)
	}
	return net.JoinHostPort(host, strconv.Itoa(port))
}

func defaultDataFile(storeEngine string) string {
	switch storeEngine {
	case store.EngineJSON:
		return "data/cityling.json"
	default:
		return "data/cityling.db"
	}
}

func envOrDefault(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func initLLMClientFromEnv() *llm.Client {
	apiKey := strings.TrimSpace(os.Getenv("CITYLING_LLM_API_KEY"))
	if apiKey == "" {
		return nil
	}

	cfg := llm.Config{
		BaseURL:             envOrDefault("CITYLING_LLM_BASE_URL", "https://api-chat.charaboard.com"),
		APIKey:              apiKey,
		AppID:               envOrDefault("CITYLING_LLM_APP_ID", "4"),
		PlatformID:          envOrDefault("CITYLING_LLM_PLATFORM_ID", "5"),
		VisionGPTType:       parseEnvInt("CITYLING_LLM_VISION_GPT_TYPE", 8102),
		TextGPTType:         parseEnvInt("CITYLING_LLM_TEXT_GPT_TYPE", 8602),
		Timeout:             time.Duration(parseEnvInt("CITYLING_LLM_TIMEOUT_SECONDS", 20)) * time.Second,
		ImageBaseURL:        envOrDefault("CITYLING_IMAGE_API_BASE_URL", "https://api-image.charaboard.com"),
		ImageAPIKey:         os.Getenv("CITYLING_IMAGE_API_KEY"),
		ImageModel:          envOrDefault("CITYLING_IMAGE_MODEL", "seedream-4-0-250828"),
		ImageResponseFormat: envOrDefault("CITYLING_IMAGE_RESPONSE_FORMAT", "b64_json"),
		VoiceBaseURL:        envOrDefault("CITYLING_TTS_API_BASE_URL", "https://api-voice.charaboard.com"),
		VoiceAPIKey:         os.Getenv("CITYLING_TTS_API_KEY"),
		VoiceID:             envOrDefault("CITYLING_TTS_VOICE_ID", "Xb7hH8MSUJpSbSDYk0k2"),
		VoiceModelID:        envOrDefault("CITYLING_TTS_MODEL_ID", "eleven_multilingual_v2"),
		VoiceLangCode:       envOrDefault("CITYLING_TTS_LANGUAGE_CODE", "zh"),
		VoiceFormat:         envOrDefault("CITYLING_TTS_OUTPUT_FORMAT", "mp3_44100_128"),
		ImageUploadScript:   envOrDefault("CITYLING_IMAGE_UPLOAD_SCRIPT_PATH", "upload.py"),
		ImageUploadPython:   envOrDefault("CITYLING_IMAGE_UPLOAD_PYTHON", "python3"),
	}

	client, err := llm.NewClient(cfg)
	if err != nil {
		log.Printf("init llm client failed: %v", err)
		return nil
	}
	return client
}

func parseEnvInt(key string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	return parseEnvIntValue(raw, fallback)
}

func parseEnvIntValue(raw string, fallback int) int {
	value, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil {
		return fallback
	}
	return value
}

func loadConfigFile(path string) error {
	file, err := os.Open(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			continue
		}
		if strings.HasPrefix(line, "export ") {
			line = strings.TrimSpace(strings.TrimPrefix(line, "export "))
		}

		sep := strings.Index(line, "=")
		if sep <= 0 {
			continue
		}

		key := strings.TrimSpace(line[:sep])
		if key == "" {
			continue
		}
		if _, exists := os.LookupEnv(key); exists {
			continue
		}

		value := strings.TrimSpace(line[sep+1:])
		value = strings.Trim(value, "\"'")
		if err := os.Setenv(key, value); err != nil {
			return err
		}
	}
	return scanner.Err()
}
