package model

import "time"

type KnowledgeItem struct {
	ObjectType string
	Aliases    []string
	Facts      []string
	Quiz       []QuizItem
}

type QuizItem struct {
	Question string
	Answer   string
}

type Spirit struct {
	ID          string    `json:"id"`
	Name        string    `json:"name"`
	ObjectType  string    `json:"object_type"`
	Personality string    `json:"personality"`
	Intro       string    `json:"intro"`
	CreatedAt   time.Time `json:"created_at"`
}

type ScanSession struct {
	ID          string    `json:"id"`
	ChildID     string    `json:"child_id"`
	ChildAge    int       `json:"child_age"`
	ObjectType  string    `json:"object_type"`
	SpiritID    string    `json:"spirit_id"`
	QuizQ       string    `json:"quiz_question"`
	QuizA       string    `json:"quiz_answer"`
	Fact        string    `json:"fact"`
	CreatedAt   time.Time `json:"created_at"`
	CacheHit    bool      `json:"cache_hit"`
	Captured    bool      `json:"captured"`
	CapturedAt  time.Time `json:"captured_at,omitempty"`
	AnswerGiven string    `json:"answer_given,omitempty"`
}

type Capture struct {
	ID         string    `json:"id"`
	ChildID    string    `json:"child_id"`
	SpiritID   string    `json:"spirit_id"`
	SpiritName string    `json:"spirit_name"`
	ObjectType string    `json:"object_type"`
	Fact       string    `json:"fact"`
	CapturedAt time.Time `json:"captured_at"`
}

type PokedexEntry struct {
	SpiritID   string    `json:"spirit_id"`
	SpiritName string    `json:"spirit_name"`
	ObjectType string    `json:"object_type"`
	Captures   int       `json:"captures"`
	LastSeenAt time.Time `json:"last_seen_at"`
}

type PokedexBadge struct {
	ID          string   `json:"id"`
	CategoryID  string   `json:"category_id"`
	Name        string   `json:"name"`
	Code        string   `json:"code"`
	Description string   `json:"description"`
	RecordScope string   `json:"record_scope"`
	Rule        string   `json:"rule"`
	ImageURL    string   `json:"image_url"`
	ImageFile   string   `json:"image_file"`
	Unlocked    bool     `json:"unlocked"`
	Progress    int      `json:"progress"`
	Target      int      `json:"target"`
	Examples    []string `json:"examples,omitempty"`
}

type DailyReport struct {
	Date            string    `json:"date"`
	ChildID         string    `json:"child_id"`
	TotalCaptured   int       `json:"total_captured"`
	Captures        []Capture `json:"captures"`
	KnowledgePoints []string  `json:"knowledge_points"`
	GeneratedText   string    `json:"generated_text"`
	GeneratedAt     time.Time `json:"generated_at"`
}
