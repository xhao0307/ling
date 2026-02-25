package llm

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var (
	ErrUploadCapabilityUnavailable = fmt.Errorf("未配置图片上传能力")
)

var uploadURLPattern = regexp.MustCompile(`https?://[^\s]+`)

// UploadImageBytesToPublicURL uploads local image bytes via the configured
// upload script (upload.py) and returns a public URL.
func (c *Client) UploadImageBytesToPublicURL(ctx context.Context, imageBytes []byte, fileName string) (string, error) {
	if len(imageBytes) == 0 {
		return "", fmt.Errorf("image bytes is empty")
	}
	script := strings.TrimSpace(c.imageUploadScript)
	pythonBin := strings.TrimSpace(c.imageUploadPython)
	if script == "" || pythonBin == "" {
		return "", ErrUploadCapabilityUnavailable
	}

	ext := strings.ToLower(strings.TrimPrefix(filepath.Ext(strings.TrimSpace(fileName)), "."))
	switch ext {
	case "jpg", "jpeg", "png", "webp":
	default:
		ext = "jpg"
	}

	tmpFile, err := os.CreateTemp("", fmt.Sprintf("cityling_upload_*.%s", ext))
	if err != nil {
		return "", err
	}
	tmpPath := tmpFile.Name()
	defer os.Remove(tmpPath)

	if _, err := tmpFile.Write(imageBytes); err != nil {
		tmpFile.Close()
		return "", err
	}
	if err := tmpFile.Close(); err != nil {
		return "", err
	}

	runCtx, cancel := context.WithTimeout(ctx, 120*time.Second)
	defer cancel()

	cmd := exec.CommandContext(runCtx, pythonBin, script, tmpPath)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("upload script failed: %w output=%s", err, strings.TrimSpace(string(output)))
	}

	text := strings.TrimSpace(string(output))
	match := uploadURLPattern.FindString(text)
	if match == "" {
		return "", fmt.Errorf("upload script output has no url: %s", text)
	}
	return strings.TrimSpace(match), nil
}

