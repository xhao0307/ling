package service

import (
	"context"
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
		store:    st,
		items:    items,
		aliases:  aliases,
		cache:    make(map[string]cacheEntry),
		cacheTTL: 5 * time.Minute,
		rng:      rand.New(rand.NewSource(time.Now().UnixNano())),
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
		return ScanResponse{}, errors.New("child_age 必须在 3 到 15 之间")
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
			// LLM 生成失败，使用知识库（如果在知识库中）
			fact = s.pick(item.Facts)
			quiz = s.pickQuiz(item.Quiz)
			if fact == "" || quiz.Question == "" {
				// 知识库与 LLM 均不可用时，返回可预期错误码（由 handler 映射为 503）。
				return ScanResponse{}, fmt.Errorf("%w: object_type=%s llm_error=%v", ErrContentGenerate, objectType, err)
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
