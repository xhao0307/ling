package service

import (
	_ "embed"
	"encoding/json"
	"os"
	"regexp"
	"sort"
	"strings"

	"ling/internal/model"
)

const defaultBadgeAssetManifestPath = "design/badges/cloud_badge_assets.json"

var (
	//go:embed badge_rules.json
	badgeRulesRawJSON []byte

	badgeTokenCleaner = regexp.MustCompile(`[\\s_\\-·（）()【】\\[\\],，。:：;；、/\\\\]+`)
)

type badgeRule struct {
	ID          string   `json:"id"`
	CategoryID  string   `json:"category_id"`
	Name        string   `json:"name"`
	Code        string   `json:"code"`
	Description string   `json:"description"`
	RecordScope string   `json:"record_scope"`
	Rule        string   `json:"rule"`
	Target      int      `json:"target"`
	ImageFile   string   `json:"image_file"`
	ImageURL    string   `json:"image_url,omitempty"`
	Keywords    []string `json:"keywords"`
	Examples    []string `json:"examples"`
}

type badgeRuleCatalog struct {
	Badges []badgeRule `json:"badges"`
}

type badgeAssetManifest struct {
	Items []badgeAssetItem `json:"items"`
}

type badgeAssetItem struct {
	BadgeID    string `json:"badge_id"`
	SourceFile string `json:"source_file"`
	ImageURL   string `json:"image_url"`
}

func loadBadgeRules() []badgeRule {
	var catalog badgeRuleCatalog
	if err := json.Unmarshal(badgeRulesRawJSON, &catalog); err != nil {
		return nil
	}
	rules := make([]badgeRule, 0, len(catalog.Badges))
	for _, rule := range catalog.Badges {
		rule.ID = strings.TrimSpace(rule.ID)
		if rule.ID == "" {
			continue
		}
		if len(rule.Examples) > 0 {
			rule.Target = len(rule.Examples)
		} else if len(rule.Keywords) > 0 {
			rule.Target = len(rule.Keywords)
		} else if rule.Target <= 0 {
			rule.Target = 1
		}
		rule.Rule = "需完成该类全部示例收集后点亮。"
		rules = append(rules, rule)
	}
	sort.Slice(rules, func(i, j int) bool {
		return rules[i].CategoryID < rules[j].CategoryID
	})
	return rules
}

func loadBadgeImageURLMap() map[string]string {
	manifestPath := strings.TrimSpace(os.Getenv("CITYLING_BADGE_ASSET_MANIFEST"))
	if manifestPath == "" {
		manifestPath = defaultBadgeAssetManifestPath
	}
	raw, err := os.ReadFile(manifestPath)
	if err != nil {
		return map[string]string{}
	}
	var manifest badgeAssetManifest
	if err := json.Unmarshal(raw, &manifest); err != nil {
		return map[string]string{}
	}
	lookup := make(map[string]string, len(manifest.Items)*2)
	for _, item := range manifest.Items {
		url := strings.TrimSpace(item.ImageURL)
		if url == "" {
			continue
		}
		if key := strings.TrimSpace(item.BadgeID); key != "" {
			lookup[key] = url
		}
		if key := strings.TrimSpace(item.SourceFile); key != "" {
			lookup[key] = url
		}
	}
	return lookup
}

func (s *Service) PokedexBadges(childID string) ([]model.PokedexBadge, error) {
	childID = strings.TrimSpace(childID)
	if childID == "" {
		childID = "guest"
	}
	captures, err := s.store.ListCapturesByChild(childID)
	if err != nil {
		return nil, err
	}
	if len(s.badgeRules) == 0 {
		return []model.PokedexBadge{}, nil
	}

	badges := make([]model.PokedexBadge, 0, len(s.badgeRules))
	for _, rule := range s.badgeRules {
		matchedObjects := make(map[string]struct{})
		for _, capture := range captures {
			objectType := strings.TrimSpace(capture.ObjectType)
			if objectType == "" {
				continue
			}
			if matchBadgeRule(rule, objectType) {
				matchedObjects[normalizeBadgeToken(objectType)] = struct{}{}
			}
		}
		progress := len(matchedObjects)
		target := rule.Target
		if target <= 0 {
			target = 1
		}
		imageURL := strings.TrimSpace(rule.ImageURL)
		if imageURL == "" {
			imageURL = strings.TrimSpace(s.badgeImageURL[rule.ID])
		}
		if imageURL == "" {
			imageURL = strings.TrimSpace(s.badgeImageURL[rule.ImageFile])
		}

		badges = append(badges, model.PokedexBadge{
			ID:          rule.ID,
			CategoryID:  rule.CategoryID,
			Name:        rule.Name,
			Code:        rule.Code,
			Description: rule.Description,
			RecordScope: rule.RecordScope,
			Rule:        rule.Rule,
			ImageURL:    imageURL,
			ImageFile:   rule.ImageFile,
			Unlocked:    progress >= target,
			Progress:    progress,
			Target:      target,
			Examples:    append([]string(nil), rule.Examples...),
		})
	}

	sort.Slice(badges, func(i, j int) bool {
		return badges[i].CategoryID < badges[j].CategoryID
	})
	return badges, nil
}

func (s *Service) isObjectTrackedByBadge(objectType string) bool {
	trimmed := strings.TrimSpace(objectType)
	if trimmed == "" {
		return false
	}
	for _, rule := range s.badgeRules {
		if matchBadgeRule(rule, trimmed) {
			return true
		}
	}
	return false
}

func matchBadgeRule(rule badgeRule, objectType string) bool {
	objectTokens := uniqueNormalizedBadgeTokens(
		objectType,
		objectTypeToChinese(objectType),
	)
	if len(objectTokens) == 0 {
		return false
	}

	if codeToken := normalizeBadgeToken(rule.Code); codeToken != "" {
		if mappedCode := normalizeBadgeToken(defaultBadgeCodeByObjectType(objectType)); mappedCode != "" && mappedCode == codeToken {
			return true
		}
		for _, objectToken := range objectTokens {
			if strings.Contains(objectToken, codeToken) || strings.Contains(codeToken, objectToken) {
				return true
			}
		}
	}

	keywords := make([]string, 0, len(rule.Keywords)+len(rule.Examples))
	keywords = append(keywords, rule.Keywords...)
	keywords = append(keywords, rule.Examples...)
	for _, keyword := range keywords {
		token := normalizeBadgeToken(keyword)
		if token == "" {
			continue
		}
		for _, objectToken := range objectTokens {
			if strings.Contains(objectToken, token) || strings.Contains(token, objectToken) {
				return true
			}
		}
	}
	return false
}

func defaultBadgeCodeByObjectType(objectType string) string {
	switch strings.TrimSpace(strings.ToLower(objectType)) {
	case "mailbox":
		return "HOME_ENVIRONMENT"
	case "manhole":
		return "MACRO_STRUCTURE"
	case "road_sign", "traffic_light":
		return "TRANSPORTATION"
	case "tree":
		return "PLANTAE"
	default:
		return ""
	}
}

func uniqueNormalizedBadgeTokens(values ...string) []string {
	seen := make(map[string]struct{}, len(values))
	tokens := make([]string, 0, len(values))
	for _, raw := range values {
		token := normalizeBadgeToken(raw)
		if token == "" {
			continue
		}
		if _, exists := seen[token]; exists {
			continue
		}
		seen[token] = struct{}{}
		tokens = append(tokens, token)
	}
	return tokens
}

func normalizeBadgeToken(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	if value == "" {
		return ""
	}
	return badgeTokenCleaner.ReplaceAllString(value, "")
}
