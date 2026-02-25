package llm

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/url"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	cos "github.com/tencentyun/cos-go-sdk-v5"
)

var (
	ErrUploadCapabilityUnavailable = fmt.Errorf("未配置图片上传能力")
)

var fileNamePattern = regexp.MustCompile(`[^a-zA-Z0-9._-]+`)

// UploadImageBytesToPublicURL uploads image bytes to a public URL via native Go COS SDK only.
func (c *Client) UploadImageBytesToPublicURL(ctx context.Context, imageBytes []byte, fileName string) (string, error) {
	if len(imageBytes) == 0 {
		return "", fmt.Errorf("image bytes is empty")
	}
	if !c.canUseCOSNativeUpload() {
		return "", ErrUploadCapabilityUnavailable
	}
	return c.uploadViaCOS(ctx, imageBytes, fileName)
}

func (c *Client) canUseCOSNativeUpload() bool {
	return strings.TrimSpace(c.cosSecretID) != "" &&
		strings.TrimSpace(c.cosSecretKey) != "" &&
		strings.TrimSpace(c.cosBucketName) != "" &&
		strings.TrimSpace(c.cosPublicDomain) != ""
}

func (c *Client) uploadViaCOS(ctx context.Context, imageBytes []byte, fileName string) (string, error) {
	bucket := strings.TrimSpace(c.cosBucketName)
	region := strings.TrimSpace(c.cosRegion)
	if region == "" {
		region = "ap-hongkong"
	}

	bucketURL, err := url.Parse(fmt.Sprintf("https://%s.cos.%s.myqcloud.com", bucket, region))
	if err != nil {
		return "", err
	}
	baseURL := &cos.BaseURL{BucketURL: bucketURL}
	client := cos.NewClient(baseURL, &http.Client{
		Transport: &cos.AuthorizationTransport{
			SecretID:  strings.TrimSpace(c.cosSecretID),
			SecretKey: strings.TrimSpace(c.cosSecretKey),
		},
	})

	key := buildUploadObjectKey(fileName)
	if _, err := client.Object.Put(ctx, key, bytes.NewReader(imageBytes), nil); err != nil {
		return "", err
	}

	publicDomain := strings.TrimRight(strings.TrimSpace(c.cosPublicDomain), "/")
	return publicDomain + "/" + key, nil
}

func buildUploadObjectKey(fileName string) string {
	clean := sanitizeFileName(fileName)
	suffix := randomHex(4)
	return fmt.Sprintf("%d_%s_%s", time.Now().Unix(), suffix, clean)
}

func sanitizeFileName(fileName string) string {
	base := strings.TrimSpace(filepath.Base(fileName))
	if base == "" || base == "." || base == "/" {
		base = "upload.jpg"
	}
	base = fileNamePattern.ReplaceAllString(base, "_")
	if base == "" {
		base = "upload.jpg"
	}
	return base
}

func randomHex(bytesLen int) string {
	if bytesLen <= 0 {
		bytesLen = 4
	}
	buf := make([]byte, bytesLen)
	if _, err := rand.Read(buf); err != nil {
		return "r"
	}
	return hex.EncodeToString(buf)
}
