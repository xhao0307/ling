package service

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"math/rand"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"ling/internal/llm"
	"ling/internal/model"
	"ling/internal/store"
)

var (
	ErrUnsupportedObject = errors.New("暂不支持该识别对象")
	ErrSessionNotFound   = errors.New("未找到对应的扫描会话")
	ErrAlreadyCaptured   = errors.New("该会话已完成收集")
	ErrLLMUnavailable    = errors.New("未配置大模型能力")
	ErrImageRequired     = errors.New("请提供 image_base64 或 image_url")
	ErrScanInputRequired = errors.New("请提供 detected_label 或 image_base64/image_url")
	ErrContentGenerate   = errors.New("学习内容生成服务暂不可用，请稍后重试")
	ErrInvalidChildAge   = errors.New("child_age 必须在 3 到 15 之间")
	ErrObjectTypeMissing = errors.New("请提供 object_type")
	ErrChildMessageEmpty = errors.New("请提供 child_message")
	ErrMediaUnavailable  = errors.New("角色形象或语音能力暂不可用")
	ErrImageUpload       = errors.New("图片上传失败")
)

type ScanRequest struct {
	ChildID       string `json:"child_id"`
	ChildAge      int    `json:"child_age"`
	DetectedLabel string `json:"detected_label"`
	ImageBase64   string `json:"image_base64,omitempty"`
	ImageURL      string `json:"image_url,omitempty"`
}

type ScanResponse struct {
	SessionID  string       `json:"session_id"`
	ObjectType string       `json:"object_type"`
	Spirit     model.Spirit `json:"spirit"`
	Fact       string       `json:"fact"`
	Quiz       string       `json:"quiz"`
	Dialogues  []string     `json:"dialogues"`
	CacheHit   bool         `json:"cache_hit"`
}

type ScanImageRequest struct {
	ChildID     string `json:"child_id"`
	ChildAge    int    `json:"child_age"`
	ImageBase64 string `json:"image_base64,omitempty"`
	ImageURL    string `json:"image_url,omitempty"`
}

type ScanImageResponse struct {
	DetectedLabel   string `json:"detected_label"`
	DetectedLabelEn string `json:"detected_label_en"`
	RawLabel        string `json:"raw_label"`
	Reason          string `json:"reason,omitempty"`
}

type AnswerRequest struct {
	SessionID string `json:"session_id"`
	ChildID   string `json:"child_id"`
	Answer    string `json:"answer"`
}

type AnswerResponse struct {
	Correct  bool           `json:"correct"`
	Captured bool           `json:"captured"`
	Message  string         `json:"message"`
	Capture  *model.Capture `json:"capture,omitempty"`
}

type CompanionSceneRequest struct {
	ChildID           string `json:"child_id"`
	ChildAge          int    `json:"child_age"`
	ObjectType        string `json:"object_type"`
	Weather           string `json:"weather,omitempty"`
	Environment       string `json:"environment,omitempty"`
	ObjectTraits      string `json:"object_traits,omitempty"`
	SourceImageBase64 string `json:"source_image_base64,omitempty"`
	SourceImageURL    string `json:"source_image_url,omitempty"`
}

type CompanionSceneResponse struct {
	CharacterName        string `json:"character_name"`
	CharacterPersonality string `json:"character_personality"`
	DialogText           string `json:"dialog_text"`
	ImagePrompt          string `json:"image_prompt"`
	CharacterImageURL    string `json:"character_image_url"`
	CharacterImageBase64 string `json:"character_image_base64,omitempty"`
	CharacterImageMIME   string `json:"character_image_mime_type,omitempty"`
	VoiceAudioBase64     string `json:"voice_audio_base64"`
	VoiceMimeType        string `json:"voice_mime_type"`
}

type CompanionChatRequest struct {
	ChildID              string   `json:"child_id"`
	ChildAge             int      `json:"child_age"`
	ObjectType           string   `json:"object_type"`
	CharacterName        string   `json:"character_name"`
	CharacterPersonality string   `json:"character_personality,omitempty"`
	Weather              string   `json:"weather,omitempty"`
	Environment          string   `json:"environment,omitempty"`
	ObjectTraits         string   `json:"object_traits,omitempty"`
	History              []string `json:"history,omitempty"`
	ChildMessage         string   `json:"child_message"`
}

type CompanionChatResponse struct {
	ReplyText        string `json:"reply_text"`
	VoiceAudioBase64 string `json:"voice_audio_base64"`
	VoiceMimeType    string `json:"voice_mime_type"`
}

type UploadImageRequest struct {
	FileName string
	Bytes    []byte
}

type UploadImageResponse struct {
	ImageURL string `json:"image_url"`
}

type cacheEntry struct {
	ObjectType string
	Spirit     model.Spirit
	Fact       string
	QuizQ      string
	QuizA      string
	Dialogues  []string
	ExpireAt   time.Time
}

type Service struct {
	store   store.Store
	items   map[string]model.KnowledgeItem
	aliases map[string]string
	llm     *llm.Client

	badgeRules    []badgeRule
	badgeImageURL map[string]string

	cacheMu  sync.RWMutex
	cache    map[string]cacheEntry
	cacheTTL time.Duration

	rngMu sync.Mutex
	rng   *rand.Rand
}

func New(st store.Store, knowledge []model.KnowledgeItem) *Service {
	items := make(map[string]model.KnowledgeItem, len(knowledge))
	aliases := make(map[string]string)
	for _, item := range knowledge {
		items[item.ObjectType] = item
		aliases[item.ObjectType] = item.ObjectType
		for _, alias := range item.Aliases {
			aliases[alias] = item.ObjectType
		}
	}

	return &Service{
		store:         st,
		items:         items,
		aliases:       aliases,
		badgeRules:    loadBadgeRules(),
		badgeImageURL: loadBadgeImageURLMap(),
		cache:         make(map[string]cacheEntry),
		cacheTTL:      5 * time.Minute,
		rng:           rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

func (s *Service) SetLLMClient(client *llm.Client) {
	s.llm = client
}

func (s *Service) ScanImage(req ScanImageRequest) (ScanImageResponse, error) {
	if s.llm == nil {
		return ScanImageResponse{}, ErrLLMUnavailable
	}
	if strings.TrimSpace(req.ImageBase64) == "" && strings.TrimSpace(req.ImageURL) == "" {
		return ScanImageResponse{}, ErrImageRequired
	}
	result, err := s.llm.RecognizeObject(context.Background(), req.ImageBase64, req.ImageURL)
	if err != nil {
		return ScanImageResponse{}, err
	}
	return ScanImageResponse{
		DetectedLabel:   objectTypeToChinese(result.ObjectType),
		DetectedLabelEn: result.ObjectType,
		RawLabel:        result.RawLabel,
		Reason:          result.Reason,
	}, nil
}

func (s *Service) Scan(req ScanRequest) (ScanResponse, error) {
	childID := strings.TrimSpace(req.ChildID)
	if childID == "" {
		childID = "guest"
	}
	if req.ChildAge < 3 || req.ChildAge > 15 {
		return ScanResponse{}, ErrInvalidChildAge
	}

	detectedLabel := strings.TrimSpace(req.DetectedLabel)
	hasImage := strings.TrimSpace(req.ImageBase64) != "" || strings.TrimSpace(req.ImageURL) != ""
	if hasImage {
		if s.llm == nil {
			return ScanResponse{}, ErrLLMUnavailable
		}
		recognized, err := s.llm.RecognizeObject(context.Background(), req.ImageBase64, req.ImageURL)
		if err != nil {
			return ScanResponse{}, err
		}
		detectedLabel = recognized.ObjectType
	}
	if detectedLabel == "" || detectedLabel == "unknown" {
		return ScanResponse{}, ErrScanInputRequired
	}

	// 尝试从知识库解析，如果不在知识库中，直接使用 detectedLabel 作为 objectType
	objectType, ok := s.resolveObjectType(detectedLabel)
	if !ok {
		// 不在知识库中，使用原始标签作为 objectType（允许任意物体）
		objectType = normalizeLabel(detectedLabel)
	}

	cacheKey := objectType + "|" + strconv.Itoa(ageBucket(req.ChildAge))
	entry, hit := s.getCache(cacheKey)
	if !hit {
		item := s.items[objectType]
		spirit := s.generateSpirit(objectType, req.ChildAge)
		if err := s.store.SaveSpirit(spirit); err != nil {
			return ScanResponse{}, err
		}

		// 优先使用 LLM 生成内容，如果不在知识库中或 LLM 失败，再使用知识库
		var fact string
		var quiz model.QuizItem
		var dialogues []string

		generated, err := s.generateLearningByLLM(objectType, req.ChildAge, spirit)
		if err == nil {
			// LLM 生成成功，使用 LLM 内容
			fact = generated.Fact
			quiz = model.QuizItem{
				Question: generated.QuizQ,
				Answer:   generated.QuizA,
			}
			dialogues = generated.Dialogues
		} else {
			// LLM 生成失败，先尝试知识库；若仍不可用则使用本地模板兜底，避免 scan 直接失败。
			fact = s.pick(item.Facts)
			quiz = s.pickQuiz(item.Quiz)
			if fact == "" || quiz.Question == "" || strings.TrimSpace(quiz.Answer) == "" {
				fact, quiz = s.defaultLearningContent(objectType)
			}
			dialogues = s.generateDialogues(spirit, req.ChildAge, fact, quiz.Question)
		}

		entry = cacheEntry{
			ObjectType: objectType,
			Spirit:     spirit,
			Fact:       fact,
			QuizQ:      quiz.Question,
			QuizA:      quiz.Answer,
			Dialogues:  dialogues,
			ExpireAt:   time.Now().Add(s.cacheTTL),
		}
		s.putCache(cacheKey, entry)
	}

	session := model.ScanSession{
		ID:         s.newID("sess"),
		ChildID:    childID,
		ChildAge:   req.ChildAge,
		ObjectType: objectType,
		SpiritID:   entry.Spirit.ID,
		QuizQ:      entry.QuizQ,
		QuizA:      strings.ToLower(strings.TrimSpace(entry.QuizA)),
		Fact:       entry.Fact,
		CreatedAt:  time.Now(),
		CacheHit:   hit,
	}
	if err := s.store.SaveSession(session); err != nil {
		return ScanResponse{}, err
	}
	dialogues := entry.Dialogues
	if len(dialogues) == 0 {
		dialogues = s.generateDialogues(entry.Spirit, req.ChildAge, entry.Fact, entry.QuizQ)
	}

	return ScanResponse{
		SessionID:  session.ID,
		ObjectType: objectType,
		Spirit:     entry.Spirit,
		Fact:       entry.Fact,
		Quiz:       entry.QuizQ,
		Dialogues:  dialogues,
		CacheHit:   hit,
	}, nil
}

func (s *Service) GenerateCompanionScene(req CompanionSceneRequest) (CompanionSceneResponse, error) {
	if req.ChildAge < 3 || req.ChildAge > 15 {
		return CompanionSceneResponse{}, ErrInvalidChildAge
	}
	objectType := strings.TrimSpace(req.ObjectType)
	if objectType == "" {
		return CompanionSceneResponse{}, ErrObjectTypeMissing
	}
	if s.llm == nil {
		return CompanionSceneResponse{}, ErrLLMUnavailable
	}

	sourceImageBase64 := strings.TrimSpace(req.SourceImageBase64)
	sourceImageURL := strings.TrimSpace(req.SourceImageURL)
	if sourceImageURL == "" && sourceImageBase64 != "" {
		// 向后兼容：旧客户端仍传 base64 时，先上传成 URL，避免下游继续使用 base64。
		uploaded, err := s.uploadBase64ToPublicURL(sourceImageBase64, "source.jpg")
		if err == nil {
			sourceImageURL = uploaded
		}
	}
	weather := strings.TrimSpace(req.Weather)
	environment := strings.TrimSpace(req.Environment)
	objectTraits := strings.TrimSpace(req.ObjectTraits)
	if sourceImageURL != "" || sourceImageBase64 != "" {
		// 图生图模式由参考图主导，不再强制注入环境参数。
		weather = ""
		environment = ""
		objectTraits = ""
	}

	scene, err := s.llm.GenerateCompanionScene(context.Background(), llm.CompanionSceneRequest{
		ObjectType:   objectType,
		ChildAge:     req.ChildAge,
		Weather:      weather,
		Environment:  environment,
		ObjectTraits: objectTraits,
	})
	if err != nil {
		scene = s.defaultCompanionScene(
			objectType,
			req.ChildAge,
			weather,
			environment,
			objectTraits,
		)
	}

	imagePrompt := scene.ImagePrompt
	if sourceImageURL != "" || sourceImageBase64 != "" {
		imagePrompt = fmt.Sprintf(
			"基于参考图进行图生图，将图中主体“%s”绘本化，保留主体外形与配色特征；如果原图只有主体或背景单调，请自动补充自然的日常生活场景背景（如公园、小区、街角、校园一角），形成前中后景层次；主体在画面中的可视面积约占1/5，位置居中或微偏中景，不能过大也不能过小；场景必须符合该主体在现实生活中的常见出现环境；整体保持童话儿童绘本风，柔和光线，画面适合作为剧情对话背景；禁止文字、水印、logo。",
			strings.TrimSpace(objectTypeToChinese(objectType)),
		)
	}

	sourceImageRef := sourceImageURL
	if sourceImageRef == "" {
		// 兼容旧客户端：上传能力不可用时继续使用原始 base64 入参。
		sourceImageRef = sourceImageBase64
	}

	imageURL, err := s.llm.GenerateCharacterImage(
		context.Background(),
		imagePrompt,
		sourceImageRef,
	)
	if err != nil {
		if errors.Is(err, llm.ErrImageCapabilityUnavailable) {
			return CompanionSceneResponse{}, ErrMediaUnavailable
		}
		return CompanionSceneResponse{}, err
	}

	audioBytes, mimeType, err := s.llm.SynthesizeSpeech(context.Background(), scene.DialogText)
	if err != nil {
		if errors.Is(err, llm.ErrVoiceCapabilityUnavailable) {
			return CompanionSceneResponse{}, ErrMediaUnavailable
		}
		return CompanionSceneResponse{}, err
	}

	imageBytes, imageMIME, err := s.llm.DownloadImage(context.Background(), imageURL)
	var imageBase64 string
	if err == nil && imageBytes != nil && len(imageBytes) > 0 {
		imageBase64 = base64.StdEncoding.EncodeToString(imageBytes)
	} else {
		// 下载失败时，不返回 base64，让前端使用 URL 加载
		imageBase64 = ""
		imageMIME = ""
	}
	if strings.HasPrefix(strings.ToLower(strings.TrimSpace(imageURL)), "data:image/") {
		// data URL 已在 base64 字段回传，避免重复放大响应体
		imageURL = ""
	}

	return CompanionSceneResponse{
		CharacterName:        scene.CharacterName,
		CharacterPersonality: scene.CharacterPersonality,
		DialogText:           scene.DialogText,
		ImagePrompt:          imagePrompt,
		CharacterImageURL:    imageURL,
		CharacterImageBase64: imageBase64,
		CharacterImageMIME:   imageMIME,
		VoiceAudioBase64:     base64.StdEncoding.EncodeToString(audioBytes),
		VoiceMimeType:        mimeType,
	}, nil
}

func (s *Service) UploadImage(req UploadImageRequest) (UploadImageResponse, error) {
	if len(req.Bytes) == 0 {
		return UploadImageResponse{}, ErrImageRequired
	}
	if s.llm == nil {
		return UploadImageResponse{}, ErrLLMUnavailable
	}
	url, err := s.llm.UploadImageBytesToPublicURL(context.Background(), req.Bytes, req.FileName)
	if err != nil {
		return UploadImageResponse{}, fmt.Errorf("%w: %v", ErrImageUpload, err)
	}
	return UploadImageResponse{ImageURL: strings.TrimSpace(url)}, nil
}

func (s *Service) uploadBase64ToPublicURL(base64Image string, fileName string) (string, error) {
	trimmed := strings.TrimSpace(base64Image)
	if trimmed == "" {
		return "", ErrImageRequired
	}
	payload := trimmed
	if strings.HasPrefix(strings.ToLower(trimmed), "data:image/") {
		idx := strings.Index(trimmed, ",")
		if idx > 0 && idx < len(trimmed)-1 {
			payload = strings.TrimSpace(trimmed[idx+1:])
		}
	}
	raw, err := base64.StdEncoding.DecodeString(payload)
	if err != nil {
		return "", err
	}
	resp, err := s.UploadImage(UploadImageRequest{
		FileName: fileName,
		Bytes:    raw,
	})
	if err != nil {
		return "", err
	}
	return resp.ImageURL, nil
}

func (s *Service) ChatCompanion(req CompanionChatRequest) (CompanionChatResponse, error) {
	if req.ChildAge < 3 || req.ChildAge > 15 {
		return CompanionChatResponse{}, ErrInvalidChildAge
	}
	objectType := strings.TrimSpace(req.ObjectType)
	if objectType == "" {
		return CompanionChatResponse{}, ErrObjectTypeMissing
	}
	childMessage := strings.TrimSpace(req.ChildMessage)
	if childMessage == "" {
		return CompanionChatResponse{}, ErrChildMessageEmpty
	}
	if s.llm == nil {
		return CompanionChatResponse{}, ErrLLMUnavailable
	}

	reply, err := s.llm.GenerateCompanionReply(context.Background(), llm.CompanionReplyRequest{
		ObjectType:           objectType,
		ChildAge:             req.ChildAge,
		CharacterName:        strings.TrimSpace(req.CharacterName),
		CharacterPersonality: strings.TrimSpace(req.CharacterPersonality),
		Weather:              strings.TrimSpace(req.Weather),
		Environment:          strings.TrimSpace(req.Environment),
		ObjectTraits:         strings.TrimSpace(req.ObjectTraits),
		History:              req.History,
		ChildMessage:         childMessage,
	})
	if err != nil {
		return CompanionChatResponse{}, err
	}

	audioBytes, mimeType, err := s.llm.SynthesizeSpeech(context.Background(), reply.ReplyText)
	if err != nil {
		if errors.Is(err, llm.ErrVoiceCapabilityUnavailable) {
			return CompanionChatResponse{}, ErrMediaUnavailable
		}
		return CompanionChatResponse{}, err
	}

	return CompanionChatResponse{
		ReplyText:        reply.ReplyText,
		VoiceAudioBase64: base64.StdEncoding.EncodeToString(audioBytes),
		VoiceMimeType:    mimeType,
	}, nil
}

func (s *Service) SubmitAnswer(req AnswerRequest) (AnswerResponse, error) {
	session, ok, err := s.store.GetSession(req.SessionID)
	if err != nil {
		return AnswerResponse{}, err
	}
	if !ok {
		return AnswerResponse{}, ErrSessionNotFound
	}
	if session.Captured {
		return AnswerResponse{}, ErrAlreadyCaptured
	}

	rawAnswer := strings.TrimSpace(req.Answer)
	answer := normalizeAnswer(rawAnswer)
	correct := isAnswerCorrect(answer, session.QuizA)
	if s.llm != nil {
		if judged, err := s.judgeAnswerByLLM(session, rawAnswer); err == nil {
			correct = judged
		}
	}
	if !correct {
		session.AnswerGiven = answer
		if err := s.store.UpdateSession(session); err != nil {
			return AnswerResponse{}, err
		}
		return AnswerResponse{
			Correct:  false,
			Captured: false,
			Message:  "答案不正确，再扫描一次获取新题目吧。",
		}, nil
	}

	if !s.isObjectTrackedByBadge(session.ObjectType) {
		session.Captured = true
		session.CapturedAt = time.Now()
		session.AnswerGiven = answer
		if err := s.store.UpdateSession(session); err != nil {
			return AnswerResponse{}, err
		}
		return AnswerResponse{
			Correct:  true,
			Captured: false,
			Message:  "回答正确，已记录识别结果；该对象不在勋章收集范围内。",
		}, nil
	}

	spiritName := "未知精灵"
	if spirit, exists, err := s.store.GetSpirit(session.SpiritID); err == nil && exists {
		spiritName = spirit.Name
	}

	capture := model.Capture{
		ID:         s.newID("cap"),
		ChildID:    session.ChildID,
		SpiritID:   session.SpiritID,
		SpiritName: spiritName,
		ObjectType: session.ObjectType,
		Fact:       session.Fact,
		CapturedAt: time.Now(),
	}
	if err := s.store.AddCapture(capture); err != nil {
		return AnswerResponse{}, err
	}

	session.Captured = true
	session.CapturedAt = capture.CapturedAt
	session.AnswerGiven = answer
	if err := s.store.UpdateSession(session); err != nil {
		return AnswerResponse{}, err
	}

	return AnswerResponse{
		Correct:  true,
		Captured: true,
		Message:  "回答正确，已成功收集精灵。",
		Capture:  &capture,
	}, nil
}

func (s *Service) judgeAnswerByLLM(session model.ScanSession, givenAnswer string) (bool, error) {
	if s.llm == nil {
		return false, ErrLLMUnavailable
	}
	result, err := s.llm.JudgeAnswer(
		context.Background(),
		session.QuizQ,
		session.QuizA,
		givenAnswer,
		session.ChildAge,
	)
	if err != nil {
		return false, err
	}
	return result.Correct, nil
}

func (s *Service) Pokedex(childID string) ([]model.PokedexEntry, error) {
	childID = strings.TrimSpace(childID)
	if childID == "" {
		childID = "guest"
	}
	captures, err := s.store.ListCapturesByChild(childID)
	if err != nil {
		return nil, err
	}

	agg := make(map[string]model.PokedexEntry)
	for _, capture := range captures {
		entry, ok := agg[capture.SpiritID]
		if !ok {
			entry = model.PokedexEntry{
				SpiritID:   capture.SpiritID,
				SpiritName: capture.SpiritName,
				ObjectType: capture.ObjectType,
				Captures:   0,
				LastSeenAt: capture.CapturedAt,
			}
		}
		entry.Captures++
		if capture.CapturedAt.After(entry.LastSeenAt) {
			entry.LastSeenAt = capture.CapturedAt
		}
		agg[capture.SpiritID] = entry
	}

	result := make([]model.PokedexEntry, 0, len(agg))
	for _, entry := range agg {
		result = append(result, entry)
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].LastSeenAt.After(result[j].LastSeenAt)
	})

	return result, nil
}

func (s *Service) DailyReport(childID string, day time.Time) (model.DailyReport, error) {
	childID = strings.TrimSpace(childID)
	if childID == "" {
		childID = "guest"
	}
	captures, err := s.store.ListCapturesByChildAndDate(childID, day)
	if err != nil {
		return model.DailyReport{}, err
	}

	knowledgeSet := make(map[string]struct{})
	for _, capture := range captures {
		knowledgeSet[capture.Fact] = struct{}{}
	}
	knowledgePoints := make([]string, 0, len(knowledgeSet))
	for point := range knowledgeSet {
		knowledgePoints = append(knowledgePoints, point)
	}
	sort.Strings(knowledgePoints)

	summary := fmt.Sprintf(
		"今天 %s 共收集了 %d 个精灵，学习了 %d 条知识点。",
		childID,
		len(captures),
		len(knowledgePoints),
	)

	return model.DailyReport{
		Date:            day.Format("2006-01-02"),
		ChildID:         childID,
		TotalCaptured:   len(captures),
		Captures:        captures,
		KnowledgePoints: knowledgePoints,
		GeneratedText:   summary,
		GeneratedAt:     time.Now(),
	}, nil
}

func (s *Service) resolveObjectType(label string) (string, bool) {
	normalized := normalizeLabel(label)
	objectType, ok := s.aliases[normalized]
	return objectType, ok
}

func normalizeLabel(v string) string {
	v = strings.ToLower(strings.TrimSpace(v))
	return strings.ReplaceAll(v, " ", "_")
}

func normalizeAnswer(v string) string {
	return strings.ToLower(strings.TrimSpace(v))
}

func isAnswerCorrect(given string, answer string) bool {
	if given == "" || answer == "" {
		return false
	}
	return given == answer || strings.Contains(given, answer) || strings.Contains(answer, given)
}

func ageBucket(age int) int {
	switch {
	case age <= 6:
		return 1
	case age <= 9:
		return 2
	default:
		return 3
	}
}

func (s *Service) getCache(key string) (cacheEntry, bool) {
	s.cacheMu.RLock()
	entry, ok := s.cache[key]
	s.cacheMu.RUnlock()
	if !ok {
		return cacheEntry{}, false
	}
	if time.Now().After(entry.ExpireAt) {
		s.cacheMu.Lock()
		delete(s.cache, key)
		s.cacheMu.Unlock()
		return cacheEntry{}, false
	}
	return entry, true
}

func (s *Service) putCache(key string, entry cacheEntry) {
	s.cacheMu.Lock()
	defer s.cacheMu.Unlock()
	s.cache[key] = entry
}

func (s *Service) newID(prefix string) string {
	return fmt.Sprintf("%s_%d", prefix, time.Now().UnixNano())
}

func (s *Service) generateSpirit(objectType string, age int) model.Spirit {
	names := map[string][]string{
		"manhole":       {"井井", "盖盖", "小阀"},
		"mailbox":       {"邮邮", "信信", "小筒"},
		"tree":          {"木木", "叶叶", "芽芽"},
		"road_sign":     {"路路", "标标", "向向"},
		"traffic_light": {"红灯灯", "绿闪闪", "信号宝"},
	}
	personalityByAge := map[int]string{
		1: "活泼好奇",
		2: "勇敢友善",
		3: "爱思考有创意",
	}
	bucket := ageBucket(age)
	choices := names[objectType]
	if len(choices) == 0 {
		choices = []string{"小灵"}
	}

	name := s.pick(choices)
	personality := personalityByAge[bucket]
	intro := fmt.Sprintf("我是%s，来自%s的城市精灵，一起学习吧。", name, objectTypeToChinese(objectType))

	return model.Spirit{
		ID:          s.newID("spirit"),
		Name:        name,
		ObjectType:  objectType,
		Personality: personality,
		Intro:       intro,
		CreatedAt:   time.Now(),
	}
}

func (s *Service) generateDialogues(spirit model.Spirit, age int, fact string, quiz string) []string {
	ageTone := "我们来一起探索城市吧。"
	switch {
	case age <= 6:
		ageTone = "慢慢来，我们一步一步发现城市秘密。"
	case age <= 9:
		ageTone = "你已经是很棒的小探索家啦。"
	default:
		ageTone = "我们用观察和思考来解锁更多知识点。"
	}

	return []string{
		fmt.Sprintf("嗨，我是%s，性格是%s。", spirit.Name, spirit.Personality),
		ageTone,
		fmt.Sprintf("我刚发现一个线索：%s", fact),
		fmt.Sprintf("轮到你回答：%s", quiz),
	}
}

func (s *Service) generateLearningByLLM(objectType string, age int, spirit model.Spirit) (llm.LearningContent, error) {
	if s.llm == nil {
		return llm.LearningContent{}, ErrLLMUnavailable
	}
	generated, err := s.llm.GenerateLearningContent(
		context.Background(),
		objectType,
		age,
		spirit.Name,
		spirit.Personality,
	)
	if err != nil {
		return llm.LearningContent{}, err
	}
	if strings.TrimSpace(generated.Fact) == "" ||
		strings.TrimSpace(generated.QuizQ) == "" ||
		strings.TrimSpace(generated.QuizA) == "" {
		return llm.LearningContent{}, llm.ErrInvalidResponse
	}
	return generated, nil
}

func (s *Service) defaultCompanionScene(objectType string, age int, weather string, environment string, traits string) llm.CompanionScene {
	objectName := strings.TrimSpace(objectTypeToChinese(objectType))
	if objectName == "" {
		objectName = strings.TrimSpace(objectType)
	}
	if objectName == "" {
		objectName = "这个小伙伴"
	}

	bucket := ageBucket(age)
	characterName := "小圆"
	personality := "活泼友好"
	switch bucket {
	case 1:
		characterName = "小圆"
		personality = "温柔可爱"
	case 2:
		characterName = "小冒险家"
		personality = "活泼好奇"
	default:
		characterName = "观察官"
		personality = "爱思考有创意"
	}

	if strings.TrimSpace(weather) == "" {
		weather = "晴天"
	}
	if strings.TrimSpace(environment) == "" {
		environment = "户外"
	}
	if strings.TrimSpace(traits) == "" {
		traits = "圆润可爱"
	}

	dialogText := fmt.Sprintf("你好呀，我是%s！今天我们一起认识%s吧。", characterName, objectName)
	imagePrompt := fmt.Sprintf(
		"儿童向二次元卡通插画，拟人化%s角色，性格%s，场景为%s的%s，物体特征%s，柔和光线，主角清晰，适合儿童",
		objectName,
		personality,
		weather,
		environment,
		traits,
	)

	return llm.CompanionScene{
		CharacterName:        characterName,
		CharacterPersonality: personality,
		DialogText:           dialogText,
		ImagePrompt:          imagePrompt,
	}
}

func (s *Service) defaultLearningContent(objectType string) (string, model.QuizItem) {
	objectName := strings.TrimSpace(objectTypeToChinese(objectType))
	if objectName == "" {
		objectName = "这个物体"
	}
	fact := fmt.Sprintf("%s是我们生活中常见的事物，认真观察它的外形和用途，就能发现很多小知识。", objectName)
	quiz := model.QuizItem{
		Question: "小挑战：我们刚刚认识的物体叫什么名字？",
		Answer:   objectName,
	}
	return fact, quiz
}

func objectTypeToChinese(objectType string) string {
	switch objectType {
	case "mailbox":
		return "邮箱"
	case "tree":
		return "树"
	case "manhole":
		return "井盖"
	case "road_sign":
		return "路牌"
	case "traffic_light":
		return "红绿灯"
	default:
		return strings.ReplaceAll(objectType, "_", " ")
	}
}

func (s *Service) pick(values []string) string {
	if len(values) == 0 {
		return ""
	}
	s.rngMu.Lock()
	defer s.rngMu.Unlock()
	return values[s.rng.Intn(len(values))]
}

func (s *Service) pickQuiz(values []model.QuizItem) model.QuizItem {
	if len(values) == 0 {
		return model.QuizItem{}
	}
	s.rngMu.Lock()
	defer s.rngMu.Unlock()
	return values[s.rng.Intn(len(values))]
}
