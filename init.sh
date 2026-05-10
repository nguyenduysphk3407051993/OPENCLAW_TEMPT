#!/bin/bash
# ==========================================
# Script khởi tạo OpenClaw trên VPS
# Chạy 1 lần duy nhất: bash init.sh
# ==========================================
set -e

echo "🚀 Đang khởi tạo OpenClaw..."

# 1. Tạo thư mục data
mkdir -p data/openclaw data/zalo data/postgres
echo "✅ Đã tạo data/openclaw, data/zalo, data/postgres"

# 2. Tạo .env từ mẫu (nếu chưa có)
if [ ! -f .env ]; then
    cp .env.example .env
    echo "✅ Đã tạo .env từ mẫu → Hãy sửa .env trước khi chạy!"
    echo "   nano .env"
else
    echo "ℹ️  .env đã tồn tại, bỏ qua."
fi

# 3. Tạo network Traefik (nếu chưa có)
if ! docker network inspect traefik-network >/dev/null 2>&1; then
    docker network create traefik-network
    echo "✅ Đã tạo docker network: traefik-network"
else
    echo "ℹ️  traefik-network đã tồn tại."
fi

echo ""
echo "=========================================="
echo "  Cấu trúc thư mục:"
echo "=========================================="
echo ""
echo "  $(pwd)/"
echo "  ├── docker/"
echo "  │   └── Dockerfile"
echo "  ├── docker-compose.yml"
echo "  ├── .env              ← SỬA FILE NÀY"
echo "  ├── .env.example"
echo "  ├── init.sh"
echo "  └── data/"
echo "      ├── openclaw/     → config, skills, extensions, workspace"
echo "      ├── zalo/         → dữ liệu Zalo"
echo "      └── postgres/     → database"
echo ""
echo "  Docker Volumes (tự động tạo khi docker compose up):"
echo "      openclaw-ai-persist  → AI packages (persist qua down/up)"
echo "      openclaw-opt-*       → repos (neural-memory, crawl4ai...)"
echo ""
echo "=========================================="
echo "  Bước tiếp theo:"
echo "=========================================="
echo ""
echo "  1. Sửa .env:          nano .env"
echo "  2. Build & chạy:      docker compose up -d --build"
echo "  3. Xem logs:          docker compose logs -f openclaw-gateway"
echo "  4. Xem AI packages:   docker compose logs openclaw-gateway | grep ai-pkg"
echo "  5. Dùng CLI:          docker compose --profile cli run --rm openclaw-cli onboard"
echo ""
echo "  💡 AI packages (OCR, embedding, RAG...) tự cài lần đầu (~10-15 phút)"
echo "     Persist trên volume → docker compose down KHÔNG mất"
echo ""
