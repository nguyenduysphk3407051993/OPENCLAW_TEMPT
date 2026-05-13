FROM ghcr.io/openclaw/openclaw:latest

LABEL org.opencontainers.image.authors="OpenClaw Community" \
      org.opencontainers.image.title="OpenClaw AI Full Setup" \
      org.opencontainers.image.description="OpenClaw - Bản cập nhật mới nhất (latest) + LaTeX, Pandoc, Gemini CLI, Crawl4AI, AI Toolkit" \
      org.opencontainers.image.version="latest-ai-fullsetup"

# ============================================
# Environment
# ============================================
ENV NODE_ENV=production \
    PNPM_HOME="/pnpm" \
    PATH="/home/openclaw/.npm-global/bin:/pnpm:/usr/local/bin:$PATH" \
    TZ=Asia/Ho_Chi_Minh \
    NO_UPDATE_NOTIFIER=true \
    HOME=/home/openclaw \
    OPENCLAW_STATE_DIR=/home/openclaw/.openclaw \
    NPM_CONFIG_PREFIX=/home/openclaw/.npm-global \
    OPENZCA_BINARY=/home/openclaw/.npm-global/lib/node_modules/openzca/dist/cli.js \
    DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1

# Image official chạy user non-root → switch root để cài system packages
USER root

# ============================================
# 0a. Cài sudo SỚM để có /etc/sudoers.d/ directory
# (Base image official không có sudo → /etc/sudoers.d không tồn tại)
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends sudo \
    && mkdir -p /etc/sudoers.d \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 0b. Defensive user setup
# Image official có thể dùng user `node` (cũ) hoặc `openclaw` (mới).
# Đảm bảo có user `openclaw` UID 1000 + sudo NOPASSWD.
# ============================================
RUN set -e; \
    if id openclaw >/dev/null 2>&1; then \
        echo "[user] openclaw đã tồn tại, skip"; \
    elif id node >/dev/null 2>&1; then \
        echo "[user] Rename node → openclaw"; \
        usermod -l openclaw node 2>/dev/null || true; \
        groupmod -n openclaw node 2>/dev/null || true; \
        if [ -d /home/node ] && [ ! -d /home/openclaw ]; then \
            mv /home/node /home/openclaw; \
        else \
            mkdir -p /home/openclaw; \
        fi; \
        usermod -d /home/openclaw openclaw 2>/dev/null || true; \
    else \
        echo "[user] Tạo mới user openclaw UID 1000"; \
        groupadd -g 1000 openclaw; \
        useradd -u 1000 -g openclaw -d /home/openclaw -m -s /bin/bash openclaw; \
    fi; \
    mkdir -p /home/openclaw; \
    chown -R openclaw:openclaw /home/openclaw 2>/dev/null || true; \
    echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/openclaw; \
    chmod 0440 /etc/sudoers.d/openclaw; \
    mkdir -p /home/openclaw/.npm-global; \
    chown -R openclaw:openclaw /home/openclaw/.npm-global; \
    echo "prefix=/home/openclaw/.npm-global" > /home/openclaw/.npmrc; \
    chown openclaw:openclaw /home/openclaw/.npmrc; \
    mkdir -p /home/node/.openclaw /home/node/.openzca /home/node/.npm-global/lib/node_modules; \
    chown -R openclaw:openclaw /home/node; \
    chmod -R u+rwX /home/node; \
    echo "[user] ✅ User setup done:"; id openclaw

# ============================================
# 1. System Dependencies
# (Image official đã có: git, curl, ca-certificates, build-essential, python3, gosu, tini)
# Vẫn cài full list bên dưới để idempotent — apt sẽ skip nếu đã có.
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates gnupg build-essential \
    python3 python3-pip python3-venv python3-pygments \
    tzdata pandoc poppler-utils ghostscript \
    fonts-noto ffmpeg nano vim jq \
    gosu sudo tini \
    apt-utils apt-transport-https software-properties-common \
    postgresql-client \
    tesseract-ocr tesseract-ocr-vie tesseract-ocr-eng \
    libgl1-mesa-glx libglib2.0-0 \
    libsndfile1 \
    cmake pkg-config \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && ln -sf /usr/sbin/gosu /usr/local/bin/gosu \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 2. TeXLive Full (~5GB)
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    texlive-full \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 3. Global NPM Tools
# (Bun, pnpm, corepack đã có sẵn trong image official → bỏ phần đó)
# ============================================
# Cài tất cả NPM tools cho user openclaw (bao gồm openzca)
RUN mkdir -p /home/openclaw/.npm-global /home/openclaw/.npm \
    && chown -R openclaw:openclaw /home/openclaw/.npm-global /home/openclaw/.npm \
    && gosu openclaw npm config set prefix /home/openclaw/.npm-global \
    && gosu openclaw npm config set cache /home/openclaw/.npm \
    && gosu openclaw npm install -g \
        acpx@latest \
        @google/gemini-cli \
        @openai/codex \
        @anthropic-ai/claude-code \
        openzca \
    && for bin in acpx gemini codex claude openzca; do \
         ln -sf "/home/openclaw/.npm-global/bin/$bin" "/usr/local/bin/$bin" 2>/dev/null || true; \
       done \
    && mkdir -p /home/node/.npm-global/lib/node_modules \
    && ln -sfn /home/openclaw/.npm-global/lib/node_modules/openzca \
           /home/node/.npm-global/lib/node_modules/openzca 2>/dev/null || true \
    && chown -R openclaw:openclaw /home/openclaw/.npm-global /home/openclaw/.npm \
    && chmod -R u+rwX /home/openclaw/.npm-global /home/openclaw/.npm

# ============================================
# 4. Python Tools: yt-dlp & Crawl4AI + Playwright
# ============================================
RUN pip3 install --no-cache-dir --break-system-packages \
    yt-dlp \
    git+https://github.com/unclecode/crawl4ai.git \
    && python3 -m playwright install-deps chromium \
    && python3 -m playwright install chromium \
    && rm -rf /tmp/playwright* /root/.cache/pip

# ============================================
# 4a. Clone repos + cài deps đầy đủ ngay khi build
# Repos được clone thẳng /opt/<name> — sẵn sàng khi container start
# ============================================

# neural-memory: chỉ cần markdown files
RUN git clone --depth 1 https://github.com/nhadaututtheky/neural-memory.git /opt/neural-memory \
    && chown -R openclaw:openclaw /opt/neural-memory

# googleworkspace-cli: clone + npm install
RUN git clone --depth 1 https://github.com/googleworkspace/cli.git /opt/googleworkspace-cli \
    && if [ -f /opt/googleworkspace-cli/package.json ]; then \
           npm install --prefix /opt/googleworkspace-cli --no-audit --no-fund --ignore-scripts; \
       fi \
    && chown -R openclaw:openclaw /opt/googleworkspace-cli

# camofox-browser: clone + pip install requirements + editable install
RUN git clone --depth 1 https://github.com/jo-inc/camofox-browser.git /opt/camofox-browser \
    && if [ -f /opt/camofox-browser/requirements.txt ]; then \
           pip3 install --no-cache-dir --break-system-packages \
               -r /opt/camofox-browser/requirements.txt; \
       fi \
    && if [ -f /opt/camofox-browser/setup.py ] || [ -f /opt/camofox-browser/pyproject.toml ]; then \
           pip3 install --no-cache-dir --break-system-packages -e /opt/camofox-browser; \
       fi \
    && rm -rf /root/.cache/pip \
    && chown -R openclaw:openclaw /opt/camofox-browser

# crawl4ai: clone source (pip package đã cài ở bước 4, ở đây lưu source để verify)
RUN git clone --depth 1 https://github.com/unclecode/crawl4ai.git /opt/crawl4ai \
    && chown -R openclaw:openclaw /opt/crawl4ai

# openzalo seed: Không cần clone nữa, sẽ cài trực tiếp qua NPM (@tuyenhx/openzalo) lúc khởi động
# ============================================
# 4c. Fix PATH trong login shell
# ============================================
RUN printf '%s\n' \
    '# OpenClaw SV — giữ PATH đúng trong mọi login shell context' \
    'export PATH="/home/openclaw/.npm-global/bin:/pnpm:/usr/local/bin:${PATH}"' \
    'export PNPM_HOME="/pnpm"' \
    'export NODE_ENV=production' \
    'export OPENCLAW_STATE_DIR=/home/openclaw/.openclaw' \
    'export NPM_CONFIG_PREFIX=/home/openclaw/.npm-global' \
    'export OPENZCA_BINARY=/home/openclaw/.npm-global/lib/node_modules/openzca/dist/cli.js' \
    'export HOME=/home/openclaw' \
    > /etc/profile.d/openclaw-path.sh \
    && sed -i 's/\r$//' /etc/profile.d/openclaw-path.sh \
    && chmod +x /etc/profile.d/openclaw-path.sh

RUN printf '#!/bin/sh\nexec node /app/dist/index.js "$@"\n' \
        > /usr/local/bin/openclaw \
    && chmod +x /usr/local/bin/openclaw

# ============================================
# 5. Permissions cho /app (image official là root:root, cần fix để user openclaw đọc được)
# Đây là fix cho vấn đề plugin-runtime-deps node_modules/openclaw EACCES
# ============================================
RUN chmod -R go+rX /app 2>/dev/null || true \
    && find /app -type d -exec chmod a+rx {} \; 2>/dev/null || true \
    && find /app -type f -exec chmod a+r {} \; 2>/dev/null || true

# ============================================
# 6. Helper Scripts
# ============================================
RUN cat > /usr/local/bin/install-pkg << 'EOF'
#!/bin/bash
set -e
echo "📦 Đang cài đặt: $@"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends "$@"
sudo rm -rf /var/lib/apt/lists/*
echo "✅ Đã cài xong: $@"
EOF

RUN cat > /usr/local/bin/install-pip << 'EOF'
#!/bin/bash
set -e
echo "🐍 Đang cài Python package: $@"
pip3 install --break-system-packages "$@"
echo "✅ Đã cài xong: $@"
EOF

RUN cat > /usr/local/bin/install-npm << 'EOF'
#!/bin/bash
set -e
echo "📦 Đang cài NPM package: $@"
sudo npm install -g "$@"
echo "✅ Đã cài xong: $@"
EOF

RUN sed -i 's/\r$//' /usr/local/bin/install-pkg /usr/local/bin/install-pip /usr/local/bin/install-npm \
    && chmod +x /usr/local/bin/install-pkg /usr/local/bin/install-pip /usr/local/bin/install-npm

# ============================================
# 7. Entrypoint Script — 6-step OpenZalo install + restore repos
# ============================================
RUN cat > /usr/local/bin/entrypoint.sh << 'ENTRY'
#!/bin/bash
set -e

GOSU="/usr/local/bin/gosu"
OPENCLAW_BIN="node /app/dist/index.js"
CONFIG_FILE="/home/openclaw/.openclaw/openclaw.json"
SEED_DIR="/opt/repos-seed"
EXT_DIR="/home/openclaw/.openclaw/extensions"
SKILLS_DIR="/home/openclaw/.openclaw/skills"
MARKER_DIR="/home/openclaw/.openclaw/.markers"

# OpenZalo paths
OPENZALO_EXT_DIR="$EXT_DIR/openzalo"
OPENZALO_TMP_DIR="/tmp/openzalo"
SEED_OPENZALO="$SEED_DIR/openzalo"

echo "=========================================="
echo "[entrypoint] OpenClaw SV v2026.4.24-sv-ai-fullsetup"
echo "[entrypoint] Args: $@"
echo "=========================================="

# ============================================
# Khởi tạo các thư mục state/workspace
# ============================================
echo "[entrypoint] 📁 Khởi tạo thư mục..."
for dir in \
    /home/openclaw/.openclaw \
    /home/openclaw/.openclaw/skills \
    /home/openclaw/.openclaw/extensions \
    /home/openclaw/.openclaw/workspace \
    /home/openclaw/.openclaw/logs \
    /home/openclaw/.openclaw/.markers \
    /home/openclaw/downloads \
    /home/openclaw/projects \
    /home/openclaw/.openzca \
    /home/openclaw/.npm-global \
    /home/openclaw/.npm \
    /home/node \
    /home/node/.openclaw \
    /home/node/.openzca \
    /home/node/.npm-global \
    /home/node/.npm-global/lib/node_modules; do
    mkdir -p "$dir" 2>/dev/null || true
done
chown -R openclaw:openclaw \
    /home/openclaw/.openclaw \
    /home/openclaw/downloads \
    /home/openclaw/projects \
    /home/openclaw/.openzca \
    /home/openclaw/.npm-global \
    /home/openclaw/.npm \
    /home/node 2>/dev/null || true

chmod -R u+rwX /home/node 2>/dev/null || true

# Đảm bảo .openclaw không bị set 700 (gây EACCES khi traverse)
chmod 755 /home/openclaw/.openclaw 2>/dev/null || true

# Dùng user openclaw cho tất cả — openzca cài tại /home/openclaw/.npm-global
export HOME=/home/openclaw
export OPENCLAW_STATE_DIR=/home/openclaw/.openclaw
export NPM_CONFIG_PREFIX=/home/openclaw/.npm-global
export OPENZCA_BINARY=/home/openclaw/.npm-global/lib/node_modules/openzca/dist/cli.js

# Đảm bảo symlink /home/node/.npm-global/lib/node_modules/openzca vẫn hợp lệ
mkdir -p /home/node/.npm-global/lib/node_modules
if [ -d /home/openclaw/.npm-global/lib/node_modules/openzca ] && \
   [ ! -e /home/node/.npm-global/lib/node_modules/openzca ]; then
    ln -sfn /home/openclaw/.npm-global/lib/node_modules/openzca \
        /home/node/.npm-global/lib/node_modules/openzca 2>/dev/null || true
fi
chown -R openclaw:openclaw /home/node/.npm-global 2>/dev/null || true
# ============================================
# HELPER: restore_repo — copy seed → /opt/<name>
# ============================================
restore_repo() {
    local name="$1"
    local url="$2"
    local dest="/opt/$name"
    local seed="$SEED_DIR/$name"

    if [ -d "$dest" ] && [ "$(ls -A "$dest" 2>/dev/null)" ]; then
        echo "[restore] ✅ $name đã có ở $dest"
        return 0
    fi
    mkdir -p "$dest"
    if [ -d "$seed" ] && [ "$(ls -A "$seed" 2>/dev/null)" ]; then
        echo "[restore] 📋 Restore $name từ seed (đã có node_modules/deps)..."
        cp -a "$seed/." "$dest/"
    else
        echo "[restore] 🌐 Seed không có — git clone $name (fallback)..."
        git clone --depth 1 "$url" "$dest" 2>&1 || \
            echo "[restore] ❌ Clone $name fail"
    fi
    chown -R openclaw:openclaw "$dest" 2>/dev/null || true
    echo "[restore] ✅ $name sẵn sàng tại $dest"
}

# ============================================
# BƯỚC 1: Restore tất cả repos ra /opt/<name>
# ============================================
echo ""
echo "[entrypoint] ━━━━━━━━━━ BƯỚC 1: RESTORE REPOS ━━━━━━━━━━"
restore_repo "neural-memory"       "https://github.com/nhadaututtheky/neural-memory.git"
restore_repo "googleworkspace-cli" "https://github.com/googleworkspace/cli.git"
restore_repo "camofox-browser"     "https://github.com/jo-inc/camofox-browser.git"
restore_repo "crawl4ai"            "https://github.com/unclecode/crawl4ai.git"

# ============================================
# BƯỚC 2: Setup từng repo (idempotent qua marker)
# ============================================
echo ""
echo "[entrypoint] ━━━━━━━━━━ BƯỚC 2: SETUP REPOS ━━━━━━━━━━"

# ----- neural-memory: sync skills *.md vào ~/.openclaw/skills/ -----
MARKER_NEURAL="$MARKER_DIR/neural-memory.done"
if [ ! -f "$MARKER_NEURAL" ] && [ -d "/opt/neural-memory" ]; then
    echo "[setup] 🧠 neural-memory: sync skills..."
    find "/opt/neural-memory" -maxdepth 2 -name "*.md" \
        -exec cp {} "$SKILLS_DIR/" \; 2>/dev/null || true
    [ -d "/opt/neural-memory/skills" ] && \
        cp -r "/opt/neural-memory/skills/." "$SKILLS_DIR/" 2>/dev/null || true
    chown -R openclaw:openclaw "$SKILLS_DIR"
    touch "$MARKER_NEURAL"
    chown openclaw:openclaw "$MARKER_NEURAL"
    echo "[setup] ✅ neural-memory skills synced ($(find "$SKILLS_DIR" -name '*.md' 2>/dev/null | wc -l) files)"
else
    echo "[setup] ✅ neural-memory: marker tồn tại, skip"
fi

# ----- googleworkspace-cli: ensure deps + symlink bin nếu có -----
MARKER_GWS="$MARKER_DIR/googleworkspace-cli.done"
if [ ! -f "$MARKER_GWS" ] && [ -d "/opt/googleworkspace-cli" ]; then
    echo "[setup] 📊 googleworkspace-cli: kiểm tra deps..."
    if [ -f "/opt/googleworkspace-cli/package.json" ] && [ ! -d "/opt/googleworkspace-cli/node_modules" ]; then
        echo "[setup]    npm install..."
        ( cd /opt/googleworkspace-cli && $GOSU openclaw npm install --no-audit --no-fund --ignore-scripts ) || \
            echo "[setup]    ⚠️  npm install lỗi"
    fi
    if [ -f "/opt/googleworkspace-cli/package.json" ]; then
        BIN_NAME=$(python3 -c "import json; d=json.load(open('/opt/googleworkspace-cli/package.json')); b=d.get('bin'); print(list(b.keys())[0] if isinstance(b, dict) else (d.get('name','').split('/')[-1] if b else ''))" 2>/dev/null || echo "")
        if [ -n "$BIN_NAME" ] && [ -f "/opt/googleworkspace-cli/$BIN_NAME" ]; then
            ln -sf "/opt/googleworkspace-cli/$BIN_NAME" "/usr/local/bin/$BIN_NAME" 2>/dev/null || true
            echo "[setup]    🔗 Symlinked: $BIN_NAME"
        fi
    fi
    touch "$MARKER_GWS"
    chown openclaw:openclaw "$MARKER_GWS"
    echo "[setup] ✅ googleworkspace-cli ready"
else
    echo "[setup] ✅ googleworkspace-cli: marker tồn tại, skip"
fi

# ----- camofox-browser: pip install -e nếu có setup.py/pyproject -----
MARKER_CAMOFOX="$MARKER_DIR/camofox-browser.done"
if [ ! -f "$MARKER_CAMOFOX" ] && [ -d "/opt/camofox-browser" ]; then
    echo "[setup] 🦊 camofox-browser: verify Python package..."
    if python3 -c "import camofox" 2>/dev/null; then
        echo "[setup] ✅ camofox-browser Python package OK (đã cài lúc build)"
    else
        echo "[setup]    🔧 Re-install camofox-browser..."
        if [ -f "/opt/camofox-browser/requirements.txt" ]; then
            pip3 install --no-cache-dir --break-system-packages \
                -r /opt/camofox-browser/requirements.txt 2>&1 | tail -n 5 || \
                echo "[setup]    ⚠️  requirements lỗi"
        fi
        if [ -f "/opt/camofox-browser/setup.py" ] || [ -f "/opt/camofox-browser/pyproject.toml" ]; then
            pip3 install --no-cache-dir --break-system-packages \
                -e /opt/camofox-browser 2>&1 | tail -n 3 || \
                echo "[setup]    ⚠️  editable install lỗi"
        fi
    fi
    touch "$MARKER_CAMOFOX"
    chown openclaw:openclaw "$MARKER_CAMOFOX"
    echo "[setup] ✅ camofox-browser ready"
else
    echo "[setup] ✅ camofox-browser: marker tồn tại, skip"
fi

# ----- crawl4ai: package đã pip install lúc build -----
MARKER_CRAWL4AI="$MARKER_DIR/crawl4ai.done"
if [ ! -f "$MARKER_CRAWL4AI" ] && [ -d "/opt/crawl4ai" ]; then
    echo "[setup] 🕷️  crawl4ai: verify Python package..."
    if python3 -c "import crawl4ai; print('crawl4ai version:', crawl4ai.__version__ if hasattr(crawl4ai,'__version__') else 'unknown')" 2>&1; then
        echo "[setup] ✅ crawl4ai Python package OK"
    else
        echo "[setup]    🔧 Re-install crawl4ai từ source..."
        pip3 install --no-cache-dir --break-system-packages \
            -e /opt/crawl4ai 2>&1 | tail -n 3 || \
            echo "[setup]    ⚠️  install lỗi"
    fi
    touch "$MARKER_CRAWL4AI"
    chown openclaw:openclaw "$MARKER_CRAWL4AI"
else
    echo "[setup] ✅ crawl4ai: marker tồn tại, skip"
fi

# ============================================
# BƯỚC 3: Sinh openclaw.json mặc định
# ============================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo ""
    echo "[entrypoint] ⚡ Sinh openclaw.json mặc định..."
    cat > "$CONFIG_FILE" << 'EOF'
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "controlUi": {
      "enabled": true,
      "dangerouslyAllowHostHeaderOriginFallback": true,
      "allowInsecureAuth": true
    },
    "auth": { "mode": "token", "token": "${OPENCLAW_GATEWAY_TOKEN}" },
    "trustedProxies": [ "0.0.0.0/0" ]
  }
}
EOF
    chown openclaw:openclaw "$CONFIG_FILE"
fi

# ============================================
# BƯỚC 4: CÀI OPENZALO PLUGIN — 6-step
# ============================================
echo ""
echo "[entrypoint] ━━━━━━━━━━ BƯỚC 4: CÀI OPENZALO ━━━━━━━━━━"

MARKER_OPENZALO="$MARKER_DIR/openzalo.done"
if [ ! -f "$MARKER_OPENZALO" ]; then
    if command -v openzca >/dev/null 2>&1; then
        echo "[openzalo] ✅ openzca có trong PATH: $(which openzca)"
    else
        echo "[openzalo] ⚠️  openzca không tìm thấy"
    fi

    echo "[openzalo] 🔌 Cài đặt plugin từ NPM (@tuyenhx/openzalo)..."
    if $GOSU openclaw $OPENCLAW_BIN plugins install @tuyenhx/openzalo 2>&1; then
        OPENZALO_OK=true
        echo "[openzalo] ✅ Plugin cài đặt thành công"
    else
        OPENZALO_OK=false
        echo "[openzalo] ❌ Cài đặt plugin thất bại — KHÔNG thêm channel config"
    fi

    if [ "$OPENZALO_OK" = "true" ]; then
        echo "[openzalo] 📝 Backup config..."
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak" 2>/dev/null || true
        chown openclaw:openclaw "$CONFIG_FILE.bak" 2>/dev/null || true

        echo "[openzalo] 📝 Thêm channels.openzalo..."
        $GOSU openclaw python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
config_file = sys.argv[1]
ZCA_BINARY = '/home/openclaw/.npm-global/lib/node_modules/openzca/dist/cli.js'

try:
    with open(config_file, 'r', encoding='utf-8') as f:
        config = json.load(f)
except Exception as e:
    print(f"[python] Doc config loi: {e}", file=sys.stderr)
    sys.exit(1)

channels = config.setdefault('channels', {})
openzalo = channels.setdefault('openzalo', {})

openzalo['enabled'] = True
openzalo['dmPolicy'] = openzalo.get('dmPolicy', 'pairing')
openzalo['groupPolicy'] = openzalo.get('groupPolicy', 'allowlist')
openzalo['groupRequireMention'] = True
openzalo['groupMentionOnly'] = True
openzalo['stripMentionFromText'] = True
openzalo['textChunkLimit'] = openzalo.get('textChunkLimit', 2000)
openzalo['zcaBinary'] = ZCA_BINARY

accounts = openzalo.setdefault('accounts', {})
default_account = accounts.setdefault('default', {})

default_account['enabled'] = True
default_account['profile'] = default_account.get('profile', 'default')
default_account['groupRequireMention'] = True
default_account['groupMentionOnly'] = True
default_account['stripMentionFromText'] = True
default_account['zcaBinary'] = ZCA_BINARY

with open(config_file, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print('[python] Da cap nhat channels.openzalo voi day du cac field moi')
PYEOF

        touch "$MARKER_OPENZALO"
        chown openclaw:openclaw "$MARKER_OPENZALO"
        echo "[openzalo] ✅ Hoàn tất! Bước thủ công còn lại:"
    fi
else
    echo "[openzalo] ✅ Đã cài (marker tồn tại trên volume)"
fi

# ============================================
# BƯỚC 5: Doctor --fix
# ============================================
echo ""
echo "[entrypoint] 🩺 doctor --fix..."
$GOSU openclaw $OPENCLAW_BIN doctor --fix --non-interactive 2>&1 || true

# ============================================
# BƯỚC 6: Build & exec final command
# ============================================
if [ $# -eq 0 ]; then
    echo "[entrypoint] ⚠️  Không có command, hiển thị help..."
    FINAL_CMD="$OPENCLAW_BIN --help"
else
    case "$1" in
        node|openclaw|/usr/local/bin/openclaw|/usr/bin/node)
            FINAL_CMD="$@"
            ;;
        bash|sh|/bin/bash|/bin/sh)
            FINAL_CMD="$@"
            ;;
        *)
            FINAL_CMD="$OPENCLAW_BIN $@"
            ;;
    esac
fi

echo ""
echo "=========================================="
echo "[entrypoint] 🚀 Exec: $FINAL_CMD"
echo "=========================================="
cd /home/openclaw/.openclaw/workspace

exec $GOSU openclaw $FINAL_CMD
ENTRY
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

# ============================================
# 8. Healthcheck & Runtime
# ============================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -sf http://localhost:18789/health || exit 1

STOPSIGNAL SIGTERM
WORKDIR /home/openclaw/.openclaw/workspace
EXPOSE 18789

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["gateway", "--bind", "lan"]