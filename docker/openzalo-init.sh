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
