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

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func initLLMClientFromEnv() *llm.Client {
	apiKey := strings.TrimSpace(os.Getenv("CITYLING_DASHSCOPE_API_KEY"))
	if apiKey == "" {
		log.Printf("llm key missing: CITYLING_DASHSCOPE_API_KEY is empty")
		return nil
	}
	legacyVoiceKey := strings.TrimSpace(os.Getenv("CITYLING_LLM_API_KEY"))
	forcedChatBaseURL := "https://dashscope.aliyuncs.com"
	forcedChatModel := "qwen3.5-flash"
	if raw := strings.TrimSpace(os.Getenv("CITYLING_LLM_BASE_URL")); raw != "" && !strings.EqualFold(strings.TrimRight(raw, "/"), forcedChatBaseURL) {
		log.Printf("llm chat base forced to %s, ignored CITYLING_LLM_BASE_URL=%s", forcedChatBaseURL, raw)
	}
	if raw := strings.TrimSpace(os.Getenv("CITYLING_LLM_MODEL")); raw != "" && !strings.EqualFold(raw, forcedChatModel) {
		log.Printf("llm chat model forced to %s, ignored CITYLING_LLM_MODEL=%s", forcedChatModel, raw)
	}

	cfg := llm.Config{
		BaseURL:              forcedChatBaseURL,
		APIKey:               apiKey,
		ChatModel:            forcedChatModel,
		AppID:                envOrDefault("CITYLING_LLM_APP_ID", "4"),
		PlatformID:           envOrDefault("CITYLING_LLM_PLATFORM_ID", "5"),
		Timeout:              time.Duration(parseEnvInt("CITYLING_LLM_TIMEOUT_SECONDS", 20)) * time.Second,
		CompanionChatTimeout: time.Duration(parseEnvInt("CITYLING_COMPANION_CHAT_TIMEOUT_SECONDS", 45)) * time.Second,
		ImageBaseURL:         firstNonEmpty(envOrDefault("CITYLING_DASHSCOPE_API_URL", ""), envOrDefault("CITYLING_IMAGE_API_BASE_URL", "https://dashscope.aliyuncs.com")),
		ImageAPIKey:          firstNonEmpty(os.Getenv("CITYLING_DASHSCOPE_API_KEY"), os.Getenv("CITYLING_IMAGE_API_KEY")),
		ImageModel:           firstNonEmpty(envOrDefault("CITYLING_DASHSCOPE_MODEL", ""), envOrDefault("CITYLING_IMAGE_MODEL", "wan2.6-image")),
		ImageResponseFormat:  envOrDefault("CITYLING_IMAGE_RESPONSE_FORMAT", "url"),
		VoiceBaseURL:         envOrDefault("CITYLING_TTS_API_BASE_URL", "https://dashscope.aliyuncs.com"),
		VoiceAPIKey:          firstNonEmpty(os.Getenv("CITYLING_TTS_API_KEY"), os.Getenv("CITYLING_DASHSCOPE_API_KEY"), legacyVoiceKey),
		VoiceID:              envOrDefault("CITYLING_TTS_VOICE_ID", "Cherry"),
		VoiceModelID:         envOrDefault("CITYLING_TTS_MODEL_ID", "qwen3-tts-flash"),
		VoiceLangCode:        envOrDefault("CITYLING_TTS_LANGUAGE_CODE", "Chinese"),
		VoiceFormat:          envOrDefault("CITYLING_TTS_OUTPUT_FORMAT", "wav"),
		TTSProfilePath:       envOrDefault("CITYLING_TTS_PROFILE_FILE", "config/tts_voice_profiles.json"),
		COSSecretID:          os.Getenv("CITYLING_COS_SECRET_ID"),
		COSSecretKey:         os.Getenv("CITYLING_COS_SECRET_KEY"),
		COSRegion:            envOrDefault("CITYLING_COS_REGION", "ap-hongkong"),
		COSBucketName:        os.Getenv("CITYLING_COS_BUCKET_NAME"),
		COSPublicDomain:      envOrDefault("CITYLING_COS_PUBLIC_DOMAIN", ""),
	}
	log.Printf(
		"llm init config: base=%s model=%s timeout=%s companion_chat_timeout=%s key_meta={%s} image_base=%s image_key_meta={%s} voice_base=%s voice_key_meta={%s}",
		cfg.BaseURL,
		cfg.ChatModel,
		cfg.Timeout.String(),
		cfg.CompanionChatTimeout.String(),
		safeKeyMeta(cfg.APIKey),
		cfg.ImageBaseURL,
		safeKeyMeta(cfg.ImageAPIKey),
		cfg.VoiceBaseURL,
		safeKeyMeta(cfg.VoiceAPIKey),
	)

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

func safeKeyMeta(key string) string {
	trimmed := strings.TrimSpace(key)
	if trimmed == "" {
		return "empty=true"
	}
	lower := strings.ToLower(trimmed)
	hasQuotes := (strings.HasPrefix(trimmed, "\"") && strings.HasSuffix(trimmed, "\"")) ||
		(strings.HasPrefix(trimmed, "'") && strings.HasSuffix(trimmed, "'"))
	return fmt.Sprintf(
		"empty=false,len=%d,starts_with_sk=%t,has_bearer_prefix=%t,has_quotes=%t,has_whitespace=%t",
		len(trimmed),
		strings.HasPrefix(trimmed, "sk-"),
		strings.HasPrefix(lower, "bearer "),
		hasQuotes,
		strings.Contains(trimmed, " "),
	)
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
