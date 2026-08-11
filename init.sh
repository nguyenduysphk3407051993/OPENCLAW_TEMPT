#!/bin/bash
# ==========================================================================
# Script TỰ ĐỘNG DỌN DẸP SẠCH & KHỞI TẠO OpenClaw + OpenZalo
# 📦 Base image: ghcr.io/openclaw/openclaw:latest (prebuilt, official)
# 👤 User: `node` (upstream-fixed, UID 1000)
# 🎯 Mục tiêu: stable, tương thích 100% với @tuyenhx/openzalo
#
# Khác biệt vs bản cũ:
#   - KHÔNG build OpenClaw từ source nữa → không còn Heap OOM
#   - KHÔNG clone OpenClaw repo, không pnpm build:docker
#   - Custom layer mỏng: chỉ thêm system deps + npm globals + plugin install
#   - Build time: 5-10 phút (vs 30-60 phút bản cũ)
#   - Image size: ~3-4GB (vs 6-8GB bản cũ)
#
# Chạy 1 lần duy nhất: bash init.sh
# ==========================================================================
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Pin version để stable, có thể đổi sang version tag cụ thể (vd. 2026.5.20)
OPENCLAW_BASE_IMAGE="${OPENCLAW_BASE_IMAGE:-ghcr.io/openclaw/openclaw:latest}"

echo -e "${BLUE}🚀 BẮT ĐẦU QUÁ TRÌNH DỌN DẸP & KHỞI TẠO LẠI...${NC}"
echo -e "${BLUE}📦 Base image: ${YELLOW}${OPENCLAW_BASE_IMAGE}${NC}"

# ==========================================================================
# KHỞI TẠO SECRETS & BIẾN MÔI TRƯỜNG
# ==========================================================================
echo -e "${BLUE}[0.5/7] 🔐 Kiểm tra và nạp secrets.env...${NC}"
if [ ! -f secrets.env ]; then
    echo -e "${YELLOW}⚠️ Chưa có file secrets.env. Đang tiến hành tạo file mẫu...${NC}"
    
    # Auto-generate some secure passwords/tokens
    AUTO_DB_PASS=$(openssl rand -hex 16)
    AUTO_GW_TOKEN=$(openssl rand -hex 32)
    
    cat > secrets.env << SECRETS_EOF
# ==========================================================================
# SECRETS CONFIGURATION
# Cảnh báo: File này chứa thông tin nhạy cảm, tuyệt đối không share hoặc commit!
# ==========================================================================

# 1. DATABASE & GATEWAY
DB_PASS=${AUTO_DB_PASS}
OPENCLAW_GATEWAY_TOKEN=${AUTO_GW_TOKEN}

# 2. CHANNELS API KEYS
TELEGRAM_BOT_TOKEN=
DISCORD_TOKEN=

# 3. AI PROVIDERS API KEYS
OPENROUTER_API_KEY=
OPENAI_API_KEY=
CLAUDIBLE_API_KEY=
NINEROUTER_API_KEY=
BAILIAN_API_KEY=
KIMI_API_KEY=
DEEPSEEK_API_KEY=

# 4. KHÁC
NOTION_API_KEY=
GITHUB_API_KEY=
CAMOFOX_API_KEY=
SECRETS_EOF
    chmod 600 secrets.env
    echo -e "${GREEN}✅ Đã tạo secrets.env với DB_PASS và OPENCLAW_GATEWAY_TOKEN tự sinh.${NC}"
    echo -e "${RED}VUI LÒNG DỪNG SCRIPT (Ctrl+C), điền các API Key vào file secrets.env rồi chạy lại script!${NC}"
    exit 1
fi

# Load variables from secrets.env
set -a
source secrets.env
set +a
echo -e "${GREEN}✅ Đã nạp biến môi trường từ secrets.env${NC}"


# ==========================================================================
# BƯỚC 0: DỌN DẸP DOCKER CŨ
# ==========================================================================
echo -e "${RED}[0/7] 🧹 Quét dọn triệt để hệ thống Docker cũ...${NC}"
if [ -f docker-compose.yml ]; then
    echo -e "${YELLOW}-> Hạ cụm dịch vụ cũ...${NC}"
    docker compose down --rmi all --volumes || true
fi
echo -e "${YELLOW}-> Xóa Build Cache...${NC}"
docker builder prune -a -f
echo -e "${YELLOW}-> System Prune...${NC}"
docker system prune -a -f
echo -e "${GREEN}✅ Hệ thống VPS đã sạch sẽ!${NC}"

# ==========================================================================
# BƯỚC 1: PULL BASE IMAGE (sớm để fail-fast nếu mạng có vấn đề)
# ==========================================================================
echo -e "${BLUE}[1/7] 📥 Pull base image upstream...${NC}"
docker pull "${OPENCLAW_BASE_IMAGE}"
echo -e "${GREEN}✅ Đã pull ${OPENCLAW_BASE_IMAGE}${NC}"

# ==========================================================================
# BƯỚC 2: TẠO CẤU TRÚC THƯ MỤC + PHÂN QUYỀN
# ==========================================================================
echo -e "${BLUE}[2/7] 📁 Tạo cấu trúc thư mục + phân quyền UID 1000 (user node)...${NC}"
mkdir -p docker data/postgres data/openclaw data/openzca
sudo chown -R 1000:1000 data/openclaw data/openzca
sudo chown -R 999:999 data/postgres 2>/dev/null || sudo chown -R 1000:1000 data/postgres
echo -e "${GREEN}✅ Done.${NC}"

# ==========================================================================
# BƯỚC 3: MẠNG ẢO
# ==========================================================================
echo -e "${BLUE}[3/7] 🌐 Kiểm tra traefik-net...${NC}"
if ! docker network inspect traefik-net >/dev/null 2>&1; then
    docker network create traefik-net
    echo -e "${GREEN}✅ Đã tạo traefik-net${NC}"
else
    echo -e "${YELLOW}ℹ️ traefik-net đã tồn tại${NC}"
fi

# ==========================================================================
# BƯỚC 4: FILE .env
# ==========================================================================
echo -e "${BLUE}[4/7] 📝 Tạo .env...${NC}"
cat > .env << ENV_EOF
##====================##
##  BASE IMAGE        ##
##====================##
# Có thể đổi sang version cụ thể như 2026.5.20 thay vì latest để ổn định hơn
OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:latest

##====================##
##  CHANNEL TOKEN     ##
##====================##
TELEGRAM_BOT_TOKEN=${TELEGRAM_BOT_TOKEN}
DISCORD_TOKEN=${DISCORD_TOKEN}

##=================================##
## GATEWAY                          ##
##=================================##
OPENCLAW_GATEWAY_TRUSTED_PROXIES=0.0.0.0/0
OPENCLAW_GATEWAY_BIND=0.0.0.0
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}

#============================================
# AI PROVIDERS
#============================================
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}

#============================================
# Domain & Timezone
#============================================
DOMAIN_NAME=edutechnd.org
SUBDOMAIN=openclaw
TZ=Asia/Ho_Chi_Minh

#==========================================
# API KEY
#==========================================
OPENAI_API_KEY=${OPENAI_API_KEY}
CLAUDIBLE_API_KEY=${CLAUDIBLE_API_KEY}
NINEROUTER_API_KEY=${NINEROUTER_API_KEY}
BAILIAN_API_KEY=${BAILIAN_API_KEY}
KIMI_API_KEY=${KIMI_API_KEY}
NOTION_API_KEY=${NOTION_API_KEY}
GITHUB_API_KEY=${GITHUB_API_KEY}
DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}
CAMOFOX_API_KEY=${CAMOFOX_API_KEY}
#==========================================
# POSTGRES
#==========================================
DB_USER=openclaw
DB_PASS=${DB_PASS}
DB_NAME=openclaw_memory

# ============================================
# VOLUME PATHS
# ============================================
OPENCLAW_DATA_DIR=./data/openclaw
OPENCLAW_OPENZCA_DIR=./data/openzca
POSTGRES_DATA_DIR=./data/postgres
ENV_EOF
chmod 600 .env
echo -e "${GREEN}✅ Done.${NC}"

# ==========================================================================
# BƯỚC 5: DOCKERFILE (CỰC GỌN - DÙNG PREBUILT BASE)
# ==========================================================================
echo -e "${BLUE}[5/7] 🛠️ Sinh docker/Dockerfile (slim layer trên prebuilt image)...${NC}"
cat > docker/Dockerfile << DOCKER_EOF
# ==========================================================================
# Custom layer trên prebuilt OpenClaw image
# - Upstream đã build sẵn OpenClaw → không cần pnpm build:docker (né OOM)
# - User \`node\` cố định (UID 1000) - không thay đổi được, đúng convention
# - Plugin openzalo hardcode /home/node/.npm-global/lib/node_modules/openzca/...
#   → npm install -g với user node tự khớp path, không cần symlink hack
# ==========================================================================
ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:latest
FROM \${OPENCLAW_BASE_IMAGE}

LABEL maintainer="edutechnd"
LABEL description="OpenClaw custom layer for Vietnamese education + OpenZalo"

# ==========================================================================
# 🧱 Layer 1: System deps cho skill giáo dục VN + browser + voice
# - texlive-full: cho skill exam-latex-creator
# - tesseract-ocr-vie: OCR tiếng Việt
# - chromium: cho browser plugin (executablePath=/usr/bin/chromium)
# - ffmpeg: BẮT BUỘC cho openzalo voice publishing (theo @tuyenhx/openzalo doc)
# - pandoc, poppler-utils: cho doc conversion
# ==========================================================================
USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        ca-certificates \
        curl \
        texlive-full \
        tesseract-ocr \
        tesseract-ocr-vie \
        tesseract-ocr-eng \
        chromium \
        ffmpeg \
        pandoc \
        poppler-utils \
        ghostscript \
        fonts-noto \
        build-essential \
        python3-dev \
        libffi-dev \
        sudo \
    && echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node \
    && chmod 0440 /etc/sudoers.d/node \
    && rm -rf /var/lib/apt/lists/* \
    && echo "✅ System deps installed" \
    && python3 -m pip install --no-cache-dir --break-system-packages --upgrade \
        pip \
        setuptools \
        wheel \
    && python3 -m pip install --no-cache-dir --break-system-packages \
        --prefer-binary \
        --timeout 120 \
        --retries 5 \
        yt-dlp \
        mutagen \
        brotli \
        websockets \
        pycryptodomex \
    && if ! python3 -m pip install --no-cache-dir --break-system-packages \
        --prefer-binary \
        --timeout 120 \
        --retries 5 \
        curl-cffi; then \
        echo "⚠️ curl-cffi not available, yt-dlp will use fallback"; \
    fi \
    && python3 -m yt_dlp --version \
    && echo "✅ yt-dlp layer OK"

# ==========================================================================
# 📦 Layer 2: NPM globals (user node) - openzca + acpx + gemini
# Cài vào /home/node/.npm-global/lib/node_modules/<pkg> - đúng path plugin
# ==========================================================================
ENV PATH="/home/node/.npm-global/bin:\${PATH}"
USER node
RUN mkdir -p /home/node/.npm-global \\
    && npm config set prefix /home/node/.npm-global \\
    && (npm install -g --no-fund --no-audit openzca acpx @google/gemini-cli || \\
        (echo "⚠️ Retry with --unsafe-perm..." && npm install -g --no-fund --no-audit --unsafe-perm openzca acpx @google/gemini-cli)) \\
    && npm cache clean --force \\
    && ls -la /home/node/.npm-global/lib/node_modules/openzca \\
    && echo "✅ openzca + acpx + gemini installed (user: node)"

# ==========================================================================
# 🚀 Layer 3: Custom entrypoint wrapper
# - Tự install @tuyenhx/openzalo plugin lần đầu boot
# - Marker-protected để không re-install mỗi lần restart
# - Sau đó chain sang command upstream (gateway --bind lan)
# ==========================================================================
USER root
# Copy entrypoint wrapper từ build context (tránh heredoc trong RUN -
# heredoc-in-RUN cần BuildKit frontend mới, không portable trên Docker cũ)
COPY docker/openzalo-init.sh /usr/local/bin/openzalo-init.sh
RUN chmod +x /usr/local/bin/openzalo-init.sh

# ==========================================================================
# 🎯 Quay về user node mặc định + override entrypoint
# Upstream CMD vẫn được preserve (gateway --bind lan tương đương)
# ==========================================================================
USER node
WORKDIR /home/node/.openclaw/workspace

# tini + init wrapper + openclaw gateway
ENTRYPOINT ["tini", "--", "/usr/local/bin/openzalo-init.sh"]
CMD ["openclaw", "gateway", "--bind", "lan"]
DOCKER_EOF
echo -e "${GREEN}✅ Đã xuất docker/Dockerfile (slim, prebuilt base).${NC}"

# ==========================================================================
# BƯỚC 5b: ENTRYPOINT WRAPPER (file riêng, COPY vào image - portable mọi Docker)
# ==========================================================================
echo -e "${BLUE}[5b] 🛠️ Sinh docker/openzalo-init.sh...${NC}"
cat > docker/openzalo-init.sh << 'INIT_EOF'
#!/bin/bash
set -e
MARKER="/home/node/.openclaw/.openzalo-installed"

# Đảm bảo thư mục tồn tại với quyền đúng
mkdir -p /home/node/.openclaw /home/node/.openzca 2>/dev/null || true
chown -R node:node /home/node/.openclaw /home/node/.openzca 2>/dev/null || true

# Install @tuyenhx/openzalo plugin lần đầu
if [ ! -f "$MARKER" ]; then
    echo "[openzalo-init] Installing @tuyenhx/openzalo plugin from npm..."
    if su -s /bin/bash node -c "cd /home/node/.openclaw && openclaw plugins install @tuyenhx/openzalo" 2>&1; then
        touch "$MARKER"
        chown node:node "$MARKER"
        echo "[openzalo-init] ✅ @tuyenhx/openzalo installed successfully"
    else
        echo "[openzalo-init] ⚠️ Plugin install failed, will retry next boot"
    fi
fi

# Chain to actual command
exec "$@"
INIT_EOF
chmod +x docker/openzalo-init.sh
echo -e "${GREEN}✅ Đã xuất docker/openzalo-init.sh.${NC}"

# ==========================================================================
# BƯỚC 6: docker-compose.yml
# ==========================================================================
echo -e "${BLUE}[6/7] 🛠️ Sinh docker-compose.yml...${NC}"
cat > docker-compose.yml << 'COMPOSE_EOF'
services:
  postgres:
    image: pgvector/pgvector:pg16
    container_name: openclaw-postgres
    restart: always
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASS}
      POSTGRES_DB: ${DB_NAME}
    volumes:
      - ${POSTGRES_DATA_DIR}:/var/lib/postgresql/data
    networks:
      - traefik-net
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}" ]
      interval: 5s
      timeout: 5s
      retries: 10

  openclaw-gateway:
    build:
      context: .
      dockerfile: docker/Dockerfile
      args:
        OPENCLAW_BASE_IMAGE: ${OPENCLAW_BASE_IMAGE:-ghcr.io/openclaw/openclaw:latest}
    image: openclaw:edutechnd
    container_name: openclaw-gateway
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    expose:
      - "18789"
    volumes:
      - ${OPENCLAW_DATA_DIR:-./data/openclaw}:/home/node/.openclaw
      - ${OPENCLAW_OPENZCA_DIR:-./data/openzca}:/home/node/.openzca
      - /etc/localtime:/etc/localtime:ro
    env_file: .env
    environment:
      - NODE_ENV=production
      - TZ=Asia/Ho_Chi_Minh
      - HOME=/home/node
      - OPENCLAW_STATE_DIR=/home/node/.openclaw
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=${DB_USER}
      - DB_PASS=${DB_PASS}
      - DB_NAME=${DB_NAME}
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      - CAMOFOX_API_KEY=${CAMOFOX_API_KEY}
    networks:
      - traefik-net
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.openclaw.rule=Host(`${SUBDOMAIN}.${DOMAIN_NAME}`)"
      - "traefik.http.routers.openclaw.entrypoints=websecure"
      - "traefik.http.routers.openclaw.tls.certresolver=myresolver"
      - "traefik.http.services.openclaw.loadbalancer.server.port=18789"
      - "traefik.http.middlewares.openclaw-headers.headers.customrequestheaders.X-Forwarded-Proto=https"
      - "traefik.http.middlewares.openclaw-compress.compress=true"
      - "traefik.http.routers.openclaw.middlewares=openclaw-headers,openclaw-compress"

  openclaw-cli:
    image: openclaw:edutechnd
    container_name: openclaw-cli
    depends_on:
      postgres:
        condition: service_healthy
      openclaw-gateway:
        condition: service_started
    volumes:
      - ${OPENCLAW_DATA_DIR:-./data/openclaw}:/home/node/.openclaw
      - ${OPENCLAW_OPENZCA_DIR:-./data/openzca}:/home/node/.openzca
      - /etc/localtime:/etc/localtime:ro
    env_file: .env
    environment:
      - NODE_ENV=production
      - TZ=Asia/Ho_Chi_Minh
      - HOME=/home/node
      - OPENCLAW_STATE_DIR=/home/node/.openclaw
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=${DB_USER}
      - DB_PASS=${DB_PASS}
      - DB_NAME=${DB_NAME}
    networks:
      - traefik-net
    tty: true
    stdin_open: true
    # Override entrypoint để vào shell, không tự start gateway
    entrypoint: ["bash"]

networks:
  traefik-net:
    external: true
COMPOSE_EOF
echo -e "${GREEN}✅ Done.${NC}"

# ==========================================================================
# BƯỚC 7: openclaw.json (paths /home/node/*, disable plugins thiếu deps)
# ==========================================================================
echo -e "${BLUE}[7/7] ⚙️ Đồng bộ openclaw.json...${NC}"

cat > data/openclaw/openclaw.json << 'JSON_EOF'
{
  "browser": {
    "enabled": true,
    "noSandbox": true,
    "executablePath": "/usr/bin/chromium",
    "headless": true,
    "evaluateEnabled": true,
    "tabCleanup": {
      "enabled": true
    }
  },
  "channels": {
    "telegram": {
      "execApprovals": {
        "enabled": true,
        "approvers": [
          7638885552
        ],
        "target": "dm"
      },
      "enabled": true,
      "dmPolicy": "allowlist",
      "allowFrom": [
        7638885552
      ],
      "groupPolicy": "allowlist",
      "streaming": {
        "mode": "off"
      },
      "groupAllowFrom": [
        "7638885552"
      ]
    },
    "discord": {
      "enabled": true,
      "token": "${DISCORD_TOKEN}",
      "groupPolicy": "allowlist",
      "streaming": {
        "mode": "off"
      },
      "allowFrom": [
        "1407787111549112432"
      ],
      "guilds": {
        "1479328314140397620": {
          "requireMention": false
        }
      },
      "execApprovals": {
        "enabled": true,
        "approvers": [
          "1407787111549112432"
        ],
        "cleanupAfterResolve": true,
        "target": "dm"
      }
    },
    "openzalo": {
      "enabled": true,
      "profile": "default",
      "dmPolicy": "allowlist",
      "groupPolicy": "allowlist",
      "groupAllowFrom": [
        "79569144045955639"
      ],
      "textChunkLimit": 2000,
      "zcaBinary": "openzca",
      "accounts": {
        "default": {
          "enabled": true,
          "profile": "default",
          "zcaBinary": "openzca"
        }
      },
      "allowFrom": [
        "5853926754769804560",
        "807704823635431192",
        "7332136520501351661",
        "6724522903641718399",
        "5679547043997806332",
        "8099433570667718475",
        "6377198547689253293",
        "6290489886789659233",
        "850216080918230753"
      ],
      "groups": {
        "79569144045955639": {
          "requireMention": true
        }
      },
      "actions": {
        "messages": true,
        "reactions": true,
        "groups": true,
        "pins": true,
        "memberInfo": true,
        "groupMembers": true
      },
      "sendTypingIndicators": true,
      "blockStreaming": false,
      "chunkMode": "length"
    }
  },
  "models": {
    "mode": "merge",
    "providers": {
      "deepseek": {
        "baseUrl": "https://api.deepseek.com",
        "apiKey": "${DEEPSEEK_API_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "deepseek-v4-flash",
            "name": "DeepSeek V4 Flash",
            "reasoning": true,
            "input": [
              "text"
            ],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0.0028,
              "cacheWrite": 0
            },
            "contextWindow": 1000000,
            "maxTokens": 384000,
            "compat": {
              "thinkingFormat": "openai"
            }
          },
          {
            "id": "deepseek-v4-pro",
            "name": "DeepSeek V4 Pro",
            "reasoning": true,
            "input": [
              "text"
            ],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0.003625,
              "cacheWrite": 0
            },
            "contextWindow": 1000000,
            "maxTokens": 384000,
            "compat": {
              "thinkingFormat": "openai"
            }
          }
        ]
      },
      "9router": {
        "baseUrl": "https://9router.edutechnd.org/v1",
        "apiKey": "${NINEROUTER_API_KEY}",
        "api": "openai-completions",
        "models": [
          {
            "id": "cx/gpt-5.6-sol",
            "name": "GPT-5.6-sol (9router)",
            "api": "openai-completions",
            "reasoning": true,
            "input": [
              "text",
              "image"
            ],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 1048576,
            "maxTokens": 65536
          },
          {
            "id": "cx/gpt-5.5",
            "name": "GPT-5.5 (9router)",
            "api": "openai-completions",
            "reasoning": true,
            "input": [
              "text",
              "image"
            ],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 1048576,
            "maxTokens": 65536
          },
          {
            "id": "cx/gpt-5.4",
            "name": "GPT-5.4 (9router)",
            "api": "openai-completions",
            "reasoning": true,
            "input": [
              "text",
              "image"
            ],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 1048576,
            "maxTokens": 65536
          },
          {
            "id": "openclaw-edutechnd-org",
            "name": "OpenClaw EduTechND Org (9router)",
            "api": "openai-completions",
            "reasoning": false,
            "input": [
              "text",
              "image"
            ],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            },
            "contextWindow": 1048576,
            "maxTokens": 65536
          }
        ]
      }
    }
  },
  "meta": {
    "lastTouchedVersion": "2026.5.20",
    "lastTouchedAt": "2026-05-25T10:36:11.748Z"
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "enabled": true,
      "dangerouslyAllowHostHeaderOriginFallback": true,
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true
    },
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    },
    "trustedProxies": [
      "0.0.0.0/0"
    ],
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "9router/cx/gpt-5.6-sol",
        "fallbacks": [
          "9router/openclaw-edutechnd-org"
        ]
      },
      "models": {
        "9router/cx/gpt-5.5": {
          "alias": "gpt-5.5 - 9router"
        },
        "9router/cx/gpt-5.4": {
          "alias": "gpt-5.4 - 9router"
        },
        "9router/cx/gpt-5.6-sol": {
          "alias": "gpt-5.6-sol - 9router"
        },
        "deepseek/deepseek-v4-flash": {},
        "deepseek/deepseek-v4-pro": {},
		"openai/gpt-5.6-sol": {
          "agentRuntime": {
            "id": "codex"
          }
        },
        "openai/gpt-5.5": {
          "agentRuntime": {
            "id": "codex"
          }
        },
        "openai/gpt-5.4": {
          "agentRuntime": {
            "id": "codex"
          }
        }
      },
      "workspace": "/home/node/.openclaw/workspace",
      "compaction": {
        "mode": "safeguard"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      },
      "sandbox": {
        "browser": {
          "enabled": true
        }
      },
      "bootstrapMaxChars": 30000,
      "bootstrapTotalMaxChars": 300000
    },
    "list": [
      {
        "id": "main",
        "default": true,
        "workspace": "/home/node/.openclaw/workspace",
        "model": {
          "primary": "9router/cx/gpt-5.5",
          "fallbacks": [
            "9router/openclaw-edutechnd-org"
          ]
        },
        "skills": [
          "supertonic-tts",
          "codex-imagen",
          "exam-latex-creator",
          "openzca",
          "prompt-video-creator",
          "browser-automation",
          "obsidian-vault-maintainer",
          "wiki-maintainer"
        ],
        "identity": {
          "name": "ELLY TIỂU MY",
          "emoji": "✨"
        },
        "subagents": {
          "allowAgents": [
            "latex-edutechnd",
            "coder-edutechnd",
            "english-edutechnd",
            "office-edutechnd",
            "prompt-edutechnd"
          ]
        },
        "tools": {
          "profile": "full"
        }
      },
      {
        "id": "latex-edutechnd",
        "workspace": "/home/node/.openclaw/workspace/latex-edutechnd",
        "model": {
          "primary": "9router/cx/gpt-5.5",
          "fallbacks": [
            "9router/openclaw-edutechnd-org"
          ]
        },
        "skills": [
          "exam-latex-creator"
        ],
        "identity": {
          "name": "LATEX_MASTER",
          "emoji": "📐"
        },
        "subagents": {
          "allowAgents": []
        },
        "tools": {
          "profile": "full"
        },
        "models": {
          "openai/gpt-5.5": {
            "agentRuntime": {
              "id": "codex"
            }
          }
        }
      },
      {
        "id": "coder-edutechnd",
        "workspace": "/home/node/.openclaw/workspace/coder-edutechnd",
        "model": {
          "primary": "9router/cx/gpt-5.5",
          "fallbacks": [
            "9router/openclaw-edutechnd-org"
          ]
        },
        "skills": [
          "oop-pyqt6-apps",
          "manim-learning-roadmap"
        ],
        "identity": {
          "name": "CODER",
          "emoji": "💻"
        },
        "subagents": {
          "allowAgents": []
        },
        "tools": {
          "profile": "full"
        }
      },
      {
        "id": "english-edutechnd",
        "workspace": "/home/node/.openclaw/workspace/english-edutechnd",
        "model": {
          "primary": "9router/cx/gpt-5.5",
          "fallbacks": [
            "9router/openclaw-edutechnd-org"
          ]
        },
        "identity": {
          "name": "TEACHER_ENG",
          "emoji": "🇬🇧"
        },
        "subagents": {
          "allowAgents": []
        },
        "tools": {
          "profile": "full"
        }
      },
      {
        "id": "office-edutechnd",
        "workspace": "/home/node/.openclaw/workspace/office-edutechnd",
        "model": {
          "primary": "9router/cx/gpt-5.5",
          "fallbacks": [
            "9router/openclaw-edutechnd-org"
          ]
        },
        "skills": [
          "gdrive-openclaw-uploader"
        ],
        "identity": {
          "name": "SECRETARY",
          "emoji": "📋"
        },
        "subagents": {
          "allowAgents": []
        },
        "tools": {
          "profile": "full"
        }
      },
      {
        "id": "prompt-edutechnd",
        "workspace": "/home/node/.openclaw/workspace/prompt-edutechnd",
        "model": {
          "primary": "9router/cx/gpt-5.5",
          "fallbacks": [
            "9router/openclaw-edutechnd-org"
          ]
        },
        "skills": [
          "prompt-image-creator",
          "prompt-video-creator",
          "codex-imagen",
          "supertonic-tts"
        ],
        "identity": {
          "name": "ART_DIRECTOR",
          "emoji": "🎨"
        },
        "subagents": {
          "allowAgents": []
        },
        "tools": {
          "profile": "full"
        }
      }
    ]
  },
  "bindings": [
    {
      "agentId": "main",
      "match": {
        "channel": "telegram"
      }
    },
    {
      "agentId": "main",
      "match": {
        "channel": "discord"
      }
    },
    {
      "agentId": "main",
      "match": {
        "channel": "openzalo"
      }
    }
  ],
  "tools": {
    "profile": "coding",
    "web": {
      "search": {
        "enabled": true,
        "provider": "kimi"
      }
    },
    "sessions": {
      "visibility": "all"
    },
    "elevated": {
      "enabled": true,
      "allowFrom": {
        "telegram": [
          7638885552
        ],
        "webchat": [
          "openclaw-control-ui",
          "*"
        ],
        "openzalo": [
          "5853926754769804560"
        ],
        "discord": [
          "1407787111549112432"
        ]
      }
    },
    "exec": {
      "security": "full",
      "ask": "off"
    },
    "alsoAllow": [
      "browser"
    ],
    "agentToAgent": {
      "enabled": true,
      "allow": [
        "prompt-edutechnd",
        "coder-edutechnd",
        "latex-edutechnd",
        "office-edutechnd",
        "english-edutechnd"
      ]
    }
  },
  "plugins": {
    "allow": [
      "browser",
      "codex",
      "deepseek",
      "discord",
      "github-copilot",
      "memory-wiki",
      "moonshot",
      "openai",
      "openzalo",
      "telegram"
    ],
    "entries": {
      "telegram": {
        "enabled": true
      },
      "openzalo": {
        "enabled": true
      },
      "discord": {
        "enabled": true
      },
      "moonshot": {
        "enabled": true,
        "config": {
          "webSearch": {
            "apiKey": "${KIMI_API_KEY}"
          }
        }
      },
      "openai": {
        "enabled": true
      },
      "browser": {
        "enabled": true
      },
      "memory-wiki": {
        "enabled": true
      },
      "neuralmemory": {
        "enabled": false
      },
      "deepseek": {
        "enabled": true
      },
      "codex": {
        "enabled": true
      },
      "github-copilot": {
        "enabled": true
      },
      "camofox-browser": {
        "enabled": false
      }
    },
    "slots": {
      "memory": "memory-wiki"
    },
    "bundledDiscovery": "allowlist"
  },
  "env": {
    "PATH": "/home/node/.local/bin:/home/node/bin:/home/node/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
    "vars": {
      "GOOGLE_PROJECT_ID": "n8n-langflow-464006",
      "GOOGLE_CLIENT_ID": "${GOOGLE_CLIENT_ID}",
      "GOOGLE_CLIENT_SECRET": "${GOOGLE_CLIENT_SECRET}",
      "GOOGLE_REDIRECT_URI": "http://localhost",
      "GOOGLE_ACCESS_TOKEN": "${GOOGLE_ACCESS_TOKEN}",
      "GOOGLE_REFRESH_TOKEN": "${GOOGLE_REFRESH_TOKEN}",
      "GOOGLE_TOKEN_TYPE": "Bearer",
      "GOOGLE_SCOPES": "https://mail.google.com/,https://www.googleapis.com/auth/spreadsheets,https://www.googleapis.com/auth/drive,https://www.googleapis.com/auth/calendar"
    }
  },
  "skills": {
    "entries": {
      "1password": {
        "enabled": false
      },
      "notion": {
        "enabled": true,
        "apiKey": "${NOTION_API_KEY}"
      },
      "apple-notes": {
        "enabled": false
      },
      "apple-reminders": {
        "enabled": false
      },
      "bear-notes": {
        "enabled": false
      },
      "blogwatcher": {
        "enabled": false
      },
      "blucli": {
        "enabled": false
      },
      "bluebubbles": {
        "enabled": false
      },
      "camsnap": {
        "enabled": false
      },
      "clawhub": {
        "enabled": false
      },
      "coding-agent": {
        "enabled": true
      },
      "eightctl": {
        "enabled": false
      },
      "gh-issues": {
        "enabled": false
      },
      "gifgrep": {
        "enabled": false
      },
      "github": {
        "enabled": true
      },
      "gog": {
        "enabled": true
      },
      "goplaces": {
        "enabled": false
      },
      "himalaya": {
        "enabled": false
      },
      "imsg": {
        "enabled": false
      },
      "mcporter": {
        "enabled": false
      },
      "model-usage": {
        "enabled": false
      },
      "nano-pdf": {
        "enabled": false
      },
      "obsidian": {
        "enabled": false
      },
      "openai-whisper": {
        "enabled": false
      },
      "openhue": {
        "enabled": false
      },
      "oracle": {
        "enabled": false
      },
      "ordercli": {
        "enabled": false
      },
      "peekaboo": {
        "enabled": false
      },
      "sag": {
        "enabled": false
      },
      "session-logs": {
        "enabled": false
      },
      "sherpa-onnx-tts": {
        "enabled": false
      },
      "slack": {
        "enabled": false
      },
      "songsee": {
        "enabled": false
      },
      "sonoscli": {
        "enabled": false
      },
      "spotify-player": {
        "enabled": false
      },
      "summarize": {
        "enabled": false
      },
      "things-mac": {
        "enabled": false
      },
      "tmux": {
        "enabled": false
      },
      "trello": {
        "enabled": false
      },
      "voice-call": {
        "enabled": false
      },
      "wacli": {
        "enabled": false
      },
      "xurl": {
        "enabled": false
      },
      "prompt-image-creator": {
        "enabled": true
      },
      "exam-latex-creator": {
        "enabled": true
      },
      "prompt-video-creator": {
        "enabled": true
      },
      "gdrive-openclaw-uploader": {
        "enabled": true
      },
      "camofox-browser": {
        "enabled": false
      },
      "codex-imagen": {
        "enabled": true
      },
      "crawl4ai-crawler": {
        "enabled": false
      },
      "oop-pyqt6-apps": {
        "enabled": true
      },
      "supertonic-tts": {
        "enabled": true
      },
      "manim-learning-roadmap": {
        "enabled": true
      }
    }
  },
  "messages": {
    "groupChat": {
      "visibleReplies": "automatic"
    }
  },
  "wizard": {
    "lastRunAt": "2026-05-24T12:17:30.566Z",
    "lastRunVersion": "2026.5.20",
    "lastRunCommand": "doctor",
    "lastRunMode": "local"
  },
  "mcp": {
    "servers": {
      "notionApi": {
        "command": "npx",
        "args": [
          "-y",
          "@notionhq/notion-mcp-server"
        ],
        "env": {
          "NOTION_TOKEN": "${NOTION_TOKEN}"
        }
      }
    }
  }
}
JSON_EOF

sudo chown -R 1000:1000 data/openclaw/

# ==========================================================================
# HOÀN TẤT
# ==========================================================================
echo ""
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}🎉 KHỞI TẠO HOÀN TẤT!${NC}"
echo -e "${GREEN}====================================================${NC}"
echo ""
echo -e "${BLUE}📋 Tóm tắt:${NC}"
echo -e "   • Base image: ${GREEN}${OPENCLAW_BASE_IMAGE}${NC}"
echo -e "   • User: ${GREEN}node${NC} (UID 1000, upstream-fixed)"
echo -e "   • OpenZalo: install từ npm ${GREEN}@tuyenhx/openzalo${NC} (lần đầu boot)"
echo -e "   • Custom layer: texlive-full + chromium + ffmpeg + tesseract-vie"
echo -e "   • Build time: ~5-10 phút (KHÔNG build OpenClaw từ source nữa)"
echo ""
echo -e "👉 ${BLUE}CÁC BƯỚC TIẾP THEO:${NC}"
echo -e "   1. Build & chạy:"
echo -e "      ${YELLOW}docker compose build && docker compose up -d${NC}"
echo ""
echo -e "   2. Theo dõi log (chờ plugin install xong):"
echo -e "      ${YELLOW}docker compose logs -f openclaw-gateway${NC}"
echo ""
echo -e "   3. Verify openzca:"
echo -e "      ${YELLOW}docker compose exec openclaw-gateway openzca --version${NC}"
echo ""
echo -e "   4. Login Zalo (theo doc @tuyenhx/openzalo):"
echo -e "      ${YELLOW}docker compose exec -it openclaw-gateway openzca --profile default auth login${NC}"
echo ""
echo -e "   5. (Optional) Pin version để stable hơn — sửa .env:"
echo -e "      ${YELLOW}OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:2026.5.20${NC}"
echo -e "${GREEN}====================================================${NC}"
