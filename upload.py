import os
import time
import sys
from qcloud_cos import CosConfig, CosS3Client

def load_dotenv(path=".env"):
    if not os.path.isfile(path):
        return
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


load_dotenv()

# ===================== 从环境变量读取配置 =====================
COS_SECRET_ID = os.getenv("CITYLING_COS_SECRET_ID", "").strip()
COS_SECRET_KEY = os.getenv("CITYLING_COS_SECRET_KEY", "").strip()
COS_REGION = os.getenv("CITYLING_COS_REGION", "ap-hongkong").strip()
COS_BUCKET_NAME = os.getenv("CITYLING_COS_BUCKET_NAME", "").strip()
COS_PUBLIC_DOMAIN = os.getenv("CITYLING_COS_PUBLIC_DOMAIN", "").strip()


def validate_env():
    missing = []
    if not COS_SECRET_ID:
        missing.append("CITYLING_COS_SECRET_ID")
    if not COS_SECRET_KEY:
        missing.append("CITYLING_COS_SECRET_KEY")
    if not COS_BUCKET_NAME:
        missing.append("CITYLING_COS_BUCKET_NAME")
    if not COS_PUBLIC_DOMAIN:
        missing.append("CITYLING_COS_PUBLIC_DOMAIN")
    if missing:
        print("❌ 缺少环境变量: " + ", ".join(missing))
        raise SystemExit(1)

# ===================== 上传图片到COS =====================
def upload_image_to_cos(local_file_path):
    # 初始化COS客户端
    config = CosConfig(
        Region=COS_REGION,
        SecretId=COS_SECRET_ID,
        SecretKey=COS_SECRET_KEY
    )
    client = CosS3Client(config)

    # 生成唯一文件名（加时间戳避免重名）
    file_name = f"{int(time.time())}_{os.path.basename(local_file_path)}"

    try:
        # 上传文件
        client.upload_file(
            Bucket=COS_BUCKET_NAME,
            LocalFilePath=local_file_path,
            Key=file_name,
            ACL="public-read"  # 关键：设置为公共读
        )
        # 拼接可访问的URL
        image_url = f"{COS_PUBLIC_DOMAIN}/{file_name}"
        print(f"✅ 上传成功，URL：{image_url}")
        return image_url
    except Exception as e:
        print(f"❌ 上传失败：{str(e)}")
        return None

# ===================== 测试上传 =====================
if __name__ == "__main__":
    validate_env()
    # 支持从命令行传入图片路径，默认仍使用 cat.png
    test_image_path = sys.argv[1] if len(sys.argv) > 1 else "./cat.png"
    if not os.path.isfile(test_image_path):
        print(f"❌ 文件不存在：{test_image_path}")
        raise SystemExit(1)
    image_url = upload_image_to_cos(test_image_path)
    if not image_url:
        raise SystemExit(1)
