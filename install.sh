#!/usr/bin/env bash
# =============================================================================
# install.sh — Clean installer cho OpenClaw SV-Pro
#  ✓ Tạo cấu trúc thư mục data/
#  ✓ Set permission đúng UID (postgres=999, openclaw=1000)
#  ✓ Đảm bảo network traefik-net tồn tại
#  ✓ Build image openclaw-pro:latest
#  ✓ Pull base images (postgres)
#  ✓ Up stack
#
# Dùng:
#   chmod +x install.sh
#   ./install.sh                  # cài full
#   ./install.sh --no-build       # chỉ up (không rebuild)
#   ./install.sh --reset          # XÓA SẠCH data/ rồi cài lại (cẩn thận!)
#   ./install.sh --lite           # build TexLive lite (~1.5GB thay vì 5GB)
#   ./install.sh --zalo           # cài rồi login Zalo
#   ./install.sh --network myname # đổi tên network
# =============================================================================
set -euo pipefail

c_red() { printf '\033[1;31m%s\033[0m\n' "$*"; }
c_grn() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_yel() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_cyn() { printf '\033[1;36m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }

DO_BUILD=1
DO_RESET=0
DO_ZALO=0
DO_LITE=0
NETWORK_NAME="${NETWORK_NAME:-traefik-net}"
ENV_TEMPLATE="${ENV_TEMPLATE:-.env_edutechnd_io_vn}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-build) DO_BUILD=0; shift ;;
    --reset)    DO_RESET=1; shift ;;
    --zalo)     DO_ZALO=1; shift ;;
    --lite)     DO_LITE=1; shift ;;
    --network)  NETWORK_NAME="$2"; shift 2 ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    *) c_red "Unknown arg: $1"; exit 1 ;;
  esac
done

cd "$(dirname "$(readlink -f "$0")")"

# 0. Pre-flight
step "0. Kiểm tra môi trường"
command -v docker >/dev/null || { c_red "Cần Docker."; exit 1; }
docker compose version >/dev/null 2>&1 || { c_red "Cần Docker Compose v2."; exit 1; }

SUDO=""
[[ "$EUID" -ne 0 ]] && command -v sudo >/dev/null && SUDO="sudo"

# 1. .env
step "1. .env"
if [[ ! -f .env ]]; then
  if [[ -f "$ENV_TEMPLATE" ]]; then
    cp "$ENV_TEMPLATE" .env
    c_grn ".env tạo từ template: $ENV_TEMPLATE"
  else
    c_yel "Tạo .env rỗng — bạn cần điền API keys sau!"
    : > .env
  fi
fi

# 2. Reset
if [[ "$DO_RESET" -eq 1 ]]; then
  step "2. RESET — xoá data/ (5s nữa, Ctrl+C để hủy)"
  sleep 5
  $SUDO rm -rf data/ || rm -rf data/
fi

# 3. Cấu trúc thư mục
step "3. Tạo cấu trúc data/"
mkdir -p \
  data/postgres \
  data/openclaw \
  data/workspace \
  data/skills \
  data/extensions \
  data/zalo \
  data/logs \
  data/hermes \
  data/downloads \
  data/projects \
  data/cache/npm \
  data/cache/npm-global \
  data/cache/pip \
  data/cache/huggingface \
  data/cache/rembg \
  data/cache/playwright \
  data/gemini \
  data/gws \
  data/claude \
  docker

# 4. Permission
step "4. Set permission (postgres=999, openclaw=1000)"
$SUDO chown -R 1000:1000 \
  data/openclaw data/workspace data/skills data/extensions \
  data/zalo data/logs data/hermes data/downloads data/projects \
  data/cache data/gemini data/gws data/claude 2>/dev/null || true

$SUDO chown -R 999:999 data/postgres 2>/dev/null || true

# 5. Network
step "5. Network: $NETWORK_NAME"
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create "$NETWORK_NAME"
  c_grn "Đã tạo network $NETWORK_NAME"
else
  c_cyn "Network $NETWORK_NAME đã tồn tại."
fi

# 6. Build
if [[ "$DO_BUILD" -eq 1 ]]; then
  if [[ "$DO_LITE" -eq 1 ]]; then
    step "6. Build (TEXLIVE_VARIANT=lite, ~1.5GB texlive)"
    DOCKER_BUILDKIT=1 TEXLIVE_VARIANT=lite docker compose build --pull openclaw-gateway
  else
    step "6. Build (TEXLIVE_VARIANT=full, ~5-6GB texlive — có thể mất 20-40 phút!)"
    DOCKER_BUILDKIT=1 docker compose build --pull openclaw-gateway
  fi
else
  c_yel "6. Bỏ qua build (--no-build)"
fi

# 7. Pull base
step "7. Pull image phụ"
docker compose pull postgres || true

# 8. Up
step "8. Up stack"
docker compose up -d postgres
sleep 3
docker compose up -d openclaw-gateway

c_grn "✓ Stack đã chạy. Theo dõi log:"
echo "    docker compose logs -f openclaw-gateway"

# 9. Bootstrap openzalo (entrypoint tự cài rồi, đây chỉ là login QR)
if [[ "$DO_ZALO" -eq 1 ]]; then
  step "9. Login Zalo (entrypoint đã tự cài plugin openzalo)"
  c_cyn "Đợi gateway boot..."
  sleep 12
  c_yel "→ QR sắp hiện. Mở Zalo điện thoại → Quét."
  docker compose exec openclaw-gateway openclaw channels login --channel openzalo || true

  cat <<EOF

$(c_grn "Sau khi quét QR:")
  1. docker compose restart openclaw-gateway
  2. Nhắn tin cho bot trên Zalo → lấy mã pairing → approve:
       docker compose exec openclaw-gateway \\
         openclaw pairing approve openzalo XXXXXXXX
EOF
fi

# 10. Tổng kết
step "✅ HOÀN TẤT"
cat <<EOF

$(c_grn "Cấu trúc data/:")
$(ls -la data/ 2>/dev/null | head -25)

$(c_grn "Lệnh hữu ích:")
  • Logs:           docker compose logs -f openclaw-gateway
  • Shell vào CLI:  docker compose --profile cli run --rm openclaw-cli bash
  • Plugins list:   docker compose exec openclaw-gateway openclaw plugins list
  • Restart GW:     docker compose restart openclaw-gateway
  • Update image:   docker compose build --pull && docker compose up -d
  • Reset all:      ./install.sh --reset --zalo

$(c_grn "Tools đã bake (gọi trực tiếp trong container):")
  • LaTeX:    pdflatex / xelatex / lualatex / latexmk
  • Office:   libreoffice (--headless), pandoc
  • Video:    yt-dlp / gallery-dl / you-get / streamlink / ffmpeg
  • PDF:      pdftk / qpdf / img2pdf / pdf2image / ocrmypdf
  • BG-rm:    rembg (PNG tách nền)
  • Dash:     streamlit / dash / dtale / ydata-profiling
  • AI CLI:   gemini / codex / claude / openzca
  • Helpers:  install-pkg / install-pip / install-npm
EOF
