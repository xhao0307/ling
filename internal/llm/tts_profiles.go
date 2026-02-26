package llm

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type ttsVoiceProfile struct {
	Name     string   `json:"name"`
	Keywords []string `json:"keywords"`
	Voices   []string `json:"voices"`
}

type ttsVoiceProfileFile struct {
	FallbackVoices []string          `json:"fallback_voices"`
	Profiles       []ttsVoiceProfile `json:"profiles"`
}

func loadTTSVoiceProfiles(path string) ([]ttsVoiceProfile, []string, error) {
	trimmedPath := strings.TrimSpace(path)
	if trimmedPath == "" {
		return defaultTTSVoiceProfiles()
	}
	raw, err := os.ReadFile(trimmedPath)
	if err != nil {
		return nil, nil, err
	}
	var file ttsVoiceProfileFile
	if err := json.Unmarshal(raw, &file); err != nil {
		return nil, nil, fmt.Errorf("parse tts profile file failed: %w", err)
	}
	profiles := make([]ttsVoiceProfile, 0, len(file.Profiles))
	for _, profile := range file.Profiles {
		voices := uniqueNonEmptyStrings(profile.Voices)
		keywords := uniqueNonEmptyStrings(profile.Keywords)
		if len(voices) == 0 || len(keywords) == 0 {
			continue
		}
		profiles = append(profiles, ttsVoiceProfile{
			Name:     strings.TrimSpace(profile.Name),
			Keywords: keywords,
			Voices:   voices,
		})
	}
	fallbackVoices := uniqueNonEmptyStrings(file.FallbackVoices)
	if len(fallbackVoices) == 0 {
		fallbackVoices = []string{"Cherry", "Serena", "Ethan"}
	}
	if len(profiles) == 0 {
		return defaultTTSVoiceProfiles()
	}
	return profiles, fallbackVoices, nil
}

func defaultTTSVoiceProfiles() ([]ttsVoiceProfile, []string, error) {
	return []ttsVoiceProfile{
			{
				Name:     "animal_lively",
				Keywords: []string{"猫", "狗", "兔", "熊", "鸟", "鱼", "鸭", "鸡", "动物", "宠物"},
				Voices:   []string{"Cherry", "Serena"},
			},
			{
				Name:     "vehicle_steady",
				Keywords: []string{"车", "火车", "地铁", "飞机", "船", "机器人", "机械"},
				Voices:   []string{"Ethan", "Serena"},
			},
			{
				Name:     "plant_gentle",
				Keywords: []string{"花", "树", "草", "叶", "水果", "蔬菜", "香蕉", "苹果", "西瓜", "植物"},
				Voices:   []string{"Serena", "Cherry"},
			},
			{
				Name:     "building_calm",
				Keywords: []string{"路灯", "红绿灯", "邮筒", "桥", "楼", "建筑", "公园"},
				Voices:   []string{"Ethan", "Cherry"},
			},
		},
		[]string{"Cherry", "Serena", "Ethan"},
		nil
}
