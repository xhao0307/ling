package llm

import (
	"os"
	"strconv"
	"strings"
)

func loadCompanionPromptSpec(path string) string {
	trimmedPath := strings.TrimSpace(path)
	if trimmedPath == "" {
		return ""
	}
	raw, err := os.ReadFile(trimmedPath)
	if err != nil {
		return ""
	}
	spec := strings.TrimSpace(strings.TrimPrefix(string(raw), "\uFEFF"))
	if spec == "" {
		return ""
	}
	return spec
}

func renderCompanionPromptSpec(spec string, childAge int, objectType string) string {
	rendered := strings.TrimSpace(spec)
	if rendered == "" {
		return ""
	}
	age := strconv.Itoa(normalizeCompanionAge(childAge))
	imageInput := strings.TrimSpace(objectType)
	if imageInput == "" {
		imageInput = "未提供图片，仅提供文本物体描述"
	}

	replacements := map[string]string{
		"{{#1771985688667.kids_age#}}":    age,
		"{{#1771985688667.image_input#}}": imageInput,
		"{{age}}":                         age,
	}
	for placeholder, value := range replacements {
		rendered = strings.ReplaceAll(rendered, placeholder, value)
	}
	return rendered
}
