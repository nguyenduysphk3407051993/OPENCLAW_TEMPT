#!/bin/bash
# =============================================================================
# OpenClaw SV-Pro entrypoint
#  6-step: dirs → restore repos → setup repos → openclaw.json → openzalo → doctor
# =============================================================================
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
echo "[entrypoint] OpenClaw SV-Pro (latest)"
echo "[entrypoint] Args: $@"
echo "=========================================="

# ============================================
# Khởi tạo các thư mục state/workspace + cache
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
    /home/openclaw/.cache/pip \
    /home/openclaw/.cache/huggingface \
    /home/openclaw/.u2net \
    /home/openclaw/.gemini \
    /home/openclaw/.config/gws \
    /home/openclaw/.claude; do
    mkdir -p "$dir" 2>/dev/null || true
done
chown -R openclaw:openclaw \
    /home/openclaw/.openclaw \
    /home/openclaw/downloads \
    /home/openclaw/projects \
    /home/openclaw/.openzca \
    /home/openclaw/.npm-global \
    /home/openclaw/.cache \
    /home/openclaw/.u2net \
    /home/openclaw/.gemini \
    /home/openclaw/.config \
    /home/openclaw/.claude 2>/dev/null || true

chmod 755 /home/openclaw/.openclaw 2>/dev/null || true

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
# BƯỚC 1: Restore repos ra /opt/<name>
# ============================================
echo ""
echo "[entrypoint] ━━━━━━━━━━ BƯỚC 1: RESTORE REPOS ━━━━━━━━━━"
restore_repo "neural-memory"       "https://github.com/nhadaututtheky/neural-memory.git"
restore_repo "googleworkspace-cli" "https://github.com/googleworkspace/cli.git"
restore_repo "camofox-browser"     "https://github.com/jo-inc/camofox-browser.git"
restore_repo "crawl4ai"            "https://github.com/unclecode/crawl4ai.git"

# ============================================
# BƯỚC 2: Setup repos (idempotent qua marker)
# ============================================
echo ""
echo "[entrypoint] ━━━━━━━━━━ BƯỚC 2: SETUP REPOS ━━━━━━━━━━"

# neural-memory: sync skills *.md vào ~/.openclaw/skills/
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
    echo "[setup] ✅ neural-memory: skip (marker)"
fi

# googleworkspace-cli: ensure deps + symlink bin
MARKER_GWS="$MARKER_DIR/googleworkspace-cli.done"
if [ ! -f "$MARKER_GWS" ] && [ -d "/opt/googleworkspace-cli" ]; then
    echo "[setup] 📊 googleworkspace-cli..."
    if [ -f "/opt/googleworkspace-cli/package.json" ] && [ ! -d "/opt/googleworkspace-cli/node_modules" ]; then
        ( cd /opt/googleworkspace-cli && $GOSU openclaw npm install --no-audit --no-fund --ignore-scripts ) || \
            echo "[setup]    ⚠️ npm install lỗi"
    fi
    if [ -f "/opt/googleworkspace-cli/package.json" ]; then
        BIN_NAME=$(python3 -c "import json; d=json.load(open('/opt/googleworkspace-cli/package.json')); b=d.get('bin'); print(list(b.keys())[0] if isinstance(b, dict) else (d.get('name','').split('/')[-1] if b else ''))" 2>/dev/null || echo "")
        if [ -n "$BIN_NAME" ] && [ -f "/opt/googleworkspace-cli/$BIN_NAME" ]; then
            ln -sf "/opt/googleworkspace-cli/$BIN_NAME" "/usr/local/bin/$BIN_NAME" 2>/dev/null || true
            echo "[setup]    🔗 Symlinked: $BIN_NAME"
        fi
    fi
    touch "$MARKER_GWS"; chown openclaw:openclaw "$MARKER_GWS"
    echo "[setup] ✅ googleworkspace-cli ready"
else
    echo "[setup] ✅ googleworkspace-cli: skip (marker)"
fi

# camofox-browser: pip install -e
MARKER_CAMOFOX="$MARKER_DIR/camofox-browser.done"
if [ ! -f "$MARKER_CAMOFOX" ] && [ -d "/opt/camofox-browser" ]; then
    echo "[setup] 🦊 camofox-browser..."
    if [ -f "/opt/camofox-browser/requirements.txt" ]; then
        pip3 install --no-cache-dir --break-system-packages \
            -r /opt/camofox-browser/requirements.txt 2>&1 | tail -n 5 || \
            echo "[setup]    ⚠️ requirements lỗi"
    fi
    if [ -f "/opt/camofox-browser/setup.py" ] || [ -f "/opt/camofox-browser/pyproject.toml" ]; then
        pip3 install --no-cache-dir --break-system-packages \
            -e /opt/camofox-browser 2>&1 | tail -n 3 || \
            echo "[setup]    ⚠️ editable install lỗi"
    fi
    touch "$MARKER_CAMOFOX"; chown openclaw:openclaw "$MARKER_CAMOFOX"
    echo "[setup] ✅ camofox-browser ready"
else
    echo "[setup] ✅ camofox-browser: skip (marker)"
fi

# crawl4ai: verify Python package
MARKER_CRAWL4AI="$MARKER_DIR/crawl4ai.done"
if [ ! -f "$MARKER_CRAWL4AI" ] && [ -d "/opt/crawl4ai" ]; then
    echo "[setup] 🕷️ crawl4ai verify..."
    if python3 -c "import crawl4ai; print('crawl4ai version:', getattr(crawl4ai,'__version__','unknown'))" 2>&1; then
        echo "[setup] ✅ crawl4ai Python OK"
    else
        echo "[setup]    🔧 Re-install crawl4ai từ source..."
        pip3 install --no-cache-dir --break-system-packages \
            -e /opt/crawl4ai 2>&1 | tail -n 3 || echo "[setup]    ⚠️ install lỗi"
    fi
    touch "$MARKER_CRAWL4AI"; chown openclaw:openclaw "$MARKER_CRAWL4AI"
else
    echo "[setup] ✅ crawl4ai: skip (marker)"
fi

# ============================================
# BƯỚC 3: openclaw.json — sinh nếu chưa có + auto-fix config cũ lỗi
# ============================================
if [ ! -f "$CONFIG_FILE" ]; then
    echo ""
    echo "[entrypoint] ⚡ Sinh openclaw.json mặc định (mode=local + bind=lan)..."
    cat > "$CONFIG_FILE" << EOF
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
    "auth": { "mode": "token", "token": "${OPENCLAW_GATEWAY_TOKEN:-}" },
    "trustedProxies": [ "0.0.0.0/0" ]
  }
}
EOF
    chown openclaw:openclaw "$CONFIG_FILE"
fi

# ---- Auto-patch config cũ (chạy mọi lần start để self-heal) ----
echo "[entrypoint] 🔧 Auto-patch openclaw.json (fix mode=remote thiếu URL + schema cũ)..."
$GOSU openclaw python3 - "$CONFIG_FILE" << 'PYFIX'
import json, sys, os
p = sys.argv[1]
if not os.path.exists(p):
    sys.exit(0)
try:
    with open(p, 'r', encoding='utf-8') as f:
        cfg = json.load(f)
except Exception as e:
    print(f"[python] Bo qua patch (config khong parse duoc): {e}")
    sys.exit(0)

changed = False

# Fix 1: gateway.mode=remote nhung thieu remote.url -> chuyen sang local
gw = cfg.setdefault('gateway', {})
if gw.get('mode') == 'remote':
    remote = gw.get('remote', {})
    if not remote.get('url'):
        print("[python] gateway.mode=remote thieu URL -> doi sang local")
        gw['mode'] = 'local'
        changed = True
gw.setdefault('bind', 'lan')

# Fix 2: channels.openzalo schema cu - chi giu key hop le
allowed_openzalo = {
    'enabled', 'dmPolicy', 'groupPolicy',
    'groupAllowFrom', 'allowFrom', 'dmAllowFrom'
}
ch = cfg.setdefault('channels', {})
oz = ch.get('openzalo')
if isinstance(oz, dict):
    bad = [k for k in list(oz.keys()) if k not in allowed_openzalo]
    if bad:
        print(f"[python] channels.openzalo - xoa key khong hop le: {bad}")
        for k in bad:
            oz.pop(k, None)
        changed = True
    # Bao dam co cac key toi thieu
    if oz.get('enabled') is None:
        oz['enabled'] = True; changed = True
    if 'dmPolicy' not in oz:
        oz['dmPolicy'] = 'pairing'; changed = True
    if 'groupPolicy' not in oz:
        oz['groupPolicy'] = 'open'; changed = True

if changed:
    with open(p + '.bak', 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    os.replace(p + '.bak', p)
    print("[python] DA PATCH config!")
else:
    print("[python] config OK, khong can patch")
PYFIX

# ============================================
# BƯỚC 4: CÀI OPENZALO PLUGIN — 6-step
# ============================================
echo ""
echo "[entrypoint] ━━━━━━━━━━ BƯỚC 4: CÀI OPENZALO ━━━━━━━━━━"

MARKER_OPENZALO="$MARKER_DIR/openzalo.done"
if [ ! -f "$MARKER_OPENZALO" ]; then
    if command -v openzca >/dev/null 2>&1; then
        echo "[openzalo] ✅ openzca: $(which openzca)"
    else
        echo "[openzalo] ⚠️ openzca không tìm thấy"
    fi

    echo "[openzalo] 📂 Chuẩn bị source tại $OPENZALO_TMP_DIR..."
    rm -rf "$OPENZALO_TMP_DIR"
    if [ -d "$SEED_OPENZALO" ] && [ "$(ls -A "$SEED_OPENZALO" 2>/dev/null)" ]; then
        cp -a "$SEED_OPENZALO" "$OPENZALO_TMP_DIR"
        echo "[openzalo] 📋 Restore từ seed"
    else
        git clone --depth 1 https://github.com/darkamenosa/openzalo.git "$OPENZALO_TMP_DIR" || \
            echo "[openzalo] ❌ Git clone fail"
        echo "[openzalo] 🌐 Cloned từ GitHub"
    fi
    chown -R openclaw:openclaw "$OPENZALO_TMP_DIR" 2>/dev/null || true

    if [ -d "$OPENZALO_TMP_DIR" ] && [ ! -d "$OPENZALO_TMP_DIR/node_modules" ]; then
        echo "[openzalo] 📥 npm install..."
        ( cd "$OPENZALO_TMP_DIR" && $GOSU openclaw npm install --no-audit --no-fund ) || \
            echo "[openzalo] ⚠️ npm install lỗi"
    fi

    if [ -d "$OPENZALO_TMP_DIR" ]; then
        echo "[openzalo] 🔌 openclaw plugins install $OPENZALO_TMP_DIR..."
        $GOSU openclaw $OPENCLAW_BIN plugins install "$OPENZALO_TMP_DIR" 2>&1 || \
            echo "[openzalo] ⚠️ plugins install non-zero (verify tiếp)"
    fi

    if [ ! -f "$OPENZALO_EXT_DIR/openclaw.plugin.json" ]; then
        echo "[openzalo] 🔧 Plugin chưa ở $OPENZALO_EXT_DIR — copy thủ công..."
        mkdir -p "$EXT_DIR"
        rm -rf "$OPENZALO_EXT_DIR"
        cp -a "$OPENZALO_TMP_DIR" "$OPENZALO_EXT_DIR" 2>/dev/null || true
        chown -R openclaw:openclaw "$OPENZALO_EXT_DIR" 2>/dev/null || true
    fi

    OPENZALO_OK=false
    if [ -f "$OPENZALO_EXT_DIR/openclaw.plugin.json" ]; then
        OPENZALO_OK=true
        echo "[openzalo] ✅ Plugin verified"
    else
        echo "[openzalo] ❌ openclaw.plugin.json KHÔNG có — KHÔNG thêm channel config"
    fi

    if [ "$OPENZALO_OK" = "true" ]; then
        echo "[openzalo] 📝 Backup config..."
        cp "$CONFIG_FILE" "$CONFIG_FILE.bak" 2>/dev/null || true
        chown openclaw:openclaw "$CONFIG_FILE.bak" 2>/dev/null || true

        echo "[openzalo] 📝 Thêm channels.openzalo (schema mới — minimal)..."
        $GOSU openclaw python3 - "$CONFIG_FILE" << 'PYEOF'
import json, sys
config_file = sys.argv[1]
try:
    with open(config_file, 'r', encoding='utf-8') as f:
        config = json.load(f)
except Exception as e:
    print(f"[python] Doc config loi: {e}", file=sys.stderr)
    sys.exit(1)
config.setdefault('channels', {})
if 'openzalo' not in config['channels']:
    # Chi giu cac key duoc schema moi cho phep
    config['channels']['openzalo'] = {
        'enabled': True,
        'dmPolicy': 'pairing',
        'groupPolicy': 'open'
    }
    with open(config_file, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)
    print('[python] Da them channels.openzalo (minimal)')
else:
    print('[python] channels.openzalo da ton tai')
PYEOF

        touch "$MARKER_OPENZALO"; chown openclaw:openclaw "$MARKER_OPENZALO"
        echo "[openzalo] ✅ Hoàn tất! Bước thủ công còn lại:"
        echo "[openzalo]    docker exec -it openclaw-gateway openclaw channels login --channel openzalo"
        echo "[openzalo]    → Quét QR (B4), rồi: openclaw pairing approve openzalo XXXXXXXX (B6)"
    else
        echo "[openzalo] ⚠️ Install fail — marker không tạo, lần sau retry"
    fi

    rm -rf "$OPENZALO_TMP_DIR" 2>/dev/null || true
else
    echo "[openzalo] ✅ Đã cài (marker tồn tại)"
fi

# ============================================
# BƯỚC 5: doctor --fix
# ============================================
echo ""
echo "[entrypoint] 🩺 doctor --fix..."
$GOSU openclaw $OPENCLAW_BIN doctor --fix --non-interactive 2>&1 || true

# ============================================
# BƯỚC 6: Build & exec final command
# ============================================
if [ $# -eq 0 ]; then
    echo "[entrypoint] ⚠️ Không có command, hiển thị help..."
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
