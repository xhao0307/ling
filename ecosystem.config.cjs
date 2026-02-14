const appName = process.env.PM2_APP_NAME || "cityling-backend";
const host = process.env.CITYLING_HOST || "0.0.0.0";
const port = process.env.CITYLING_PORT || "8082";

module.exports = {
  apps: [
    {
      name: appName,
      cwd: __dirname,
      script: "./bin/cityling-server",
      interpreter: "none",
      args: ["-host", host, "-port", port],
      time: true,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 1000,
      env: {
        CITYLING_STORE: process.env.CITYLING_STORE || "sqlite",
        CITYLING_DATA_FILE:
          process.env.CITYLING_DATA_FILE || "data/cityling.db",
        CITYLING_LLM_API_KEY: process.env.CITYLING_LLM_API_KEY || "",
        CITYLING_LLM_BASE_URL:
          process.env.CITYLING_LLM_BASE_URL || "https://api-chat.charaboard.com",
        CITYLING_LLM_APP_ID: process.env.CITYLING_LLM_APP_ID || "4",
        CITYLING_LLM_PLATFORM_ID: process.env.CITYLING_LLM_PLATFORM_ID || "5",
        CITYLING_LLM_VISION_GPT_TYPE:
          process.env.CITYLING_LLM_VISION_GPT_TYPE || "8102",
        CITYLING_LLM_TEXT_GPT_TYPE:
          process.env.CITYLING_LLM_TEXT_GPT_TYPE || "8602",
        CITYLING_LLM_TIMEOUT_SECONDS:
          process.env.CITYLING_LLM_TIMEOUT_SECONDS || "20",
      },
    },
  ],
};

