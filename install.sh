#!/usr/bin/env bash
# =============================================================================
# install.sh — Fresh-install installer cho OpenClaw SV-Pro
#
#  ⚡ DEFAULT BEHAVIOR = CÀI MỚI HOÀN TOÀN:
#     1. Stop + remove containers cũ (down -v --remove-orphans)
#     2. Xoá image openclaw-pro:latest cũ (kể cả image lỗi/dangling)
#     3. Prune toàn bộ build cache + dangling images
#     4. Xoá thư mục data/ host (postgres, openclaw, zalo, cache…)
#     5. Tạo lại cấu trúc folder + permission
#     6. Tạo network traefik-net nếu chưa có
#     7. Build image openclaw-pro:latest --no-cache --pull
#     8. Pull postgres
#     9. Up stack
#
#  ⚠️ Default sẽ XÓA SẠCH data/ — có 10 giây countdown để Ctrl+C hủy
#
#  Flags:
#     --keep-data       Không xoá data/ (giữ postgres DB, zalo session)
#     --keep-cache      Không prune build cache (rebuild nhanh hơn)
#     --keep-image      Không xoá image cũ (dùng cache layer cũ)
#     --soft            = --keep-data --keep-cache --keep-image (chỉ up lại)
#     --lite            Build TexLive variant=lite (~1.5GB thay vì 5GB)
#     --no-build        Bỏ qua bước build
#     --zalo            Login Zalo QR sau khi up
#     --network NAME    Đặt tên network (mặc định: traefik-net)
#     --yes / -y        Bỏ qua countdown 10 giây
#     -h | --help       In help này
# =============================================================================
set -euo pipefail

# ---------- Color helpers ----------
c_red() { printf '\033[1;31m%s\033[0m\n' "$*"; }
c_grn() { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_yel() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_cyn() { printf '\033[1;36m%s\033[0m\n' "$*"; }
c_mag() { printf '\033[1;35m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }

# ---------- Defaults: FRESH INSTALL ----------
KEEP_DATA=0
KEEP_CACHE=0
KEEP_IMAGE=0
DO_BUILD=1
DO_LITE=0
DO_ZALO=0
SKIP_CONFIRM=0
NETWORK_NAME="${NETWORK_NAME:-traefik-net}"
ENV_TEMPLATE="${ENV_TEMPLATE:-.env_edutechnd_io_vn}"
IMAGE_NAME="openclaw-pro:latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-data)   KEEP_DATA=1; shift ;;
    --keep-cache)  KEEP_CACHE=1; shift ;;
    --keep-image)  KEEP_IMAGE=1; shift ;;
    --soft)        KEEP_DATA=1; KEEP_CACHE=1; KEEP_IMAGE=1; shift ;;
    --no-build)    DO_BUILD=0; shift ;;
    --lite)        DO_LITE=1; shift ;;
    --zalo)        DO_ZALO=1; shift ;;
    --yes|-y)      SKIP_CONFIRM=1; shift ;;
    --network)     NETWORK_NAME="$2"; shift 2 ;;
    -h|--help)     sed -n '2,28p' "$0"; exit 0 ;;
    *) c_red "Unknown arg: $1 (xem --help)"; exit 1 ;;
  esac
done

cd "$(dirname "$(readlink -f "$0")")"

SUDO=""
[[ "$EUID" -ne 0 ]] && command -v sudo >/dev/null && SUDO="sudo"

# ============================================================================
# 0. PRE-FLIGHT
# ============================================================================
step "0. Kiểm tra môi trường"
command -v docker >/dev/null || { c_red "Cần Docker."; exit 1; }
docker compose version >/dev/null 2>&1 || { c_red "Cần Docker Compose v2."; exit 1; }
c_grn "✓ Docker $(docker --version | awk '{print $3}' | tr -d ',')"
c_grn "✓ Compose $(docker compose version --short)"
c_grn "✓ Disk free: $(df -h . | awk 'NR==2 {print $4}')"

# ============================================================================
# 1. WARNING + COUNTDOWN
# ============================================================================
step "1. KẾ HOẠCH CÀI MỚI"
echo "    [$( [[ $KEEP_IMAGE -eq 0 ]] && echo "✅" || echo "⏭️ ")] Xoá image cũ        ($IMAGE_NAME)"
echo "    [$( [[ $KEEP_CACHE -eq 0 ]] && echo "✅" || echo "⏭️ ")] Prune build cache    (docker builder prune -af)"
echo "    [$( [[ $KEEP_DATA  -eq 0 ]] && echo "✅" || echo "⏭️ ")] Xoá data/ host       (postgres, openclaw, zalo, cache…)"
echo "    [✅] Stop & remove containers cũ"
echo "    [✅] Tạo lại cấu trúc + permission"
echo "    [✅] Build $( [[ $DO_LITE -eq 1 ]] && echo "(LITE)" || echo "(FULL)" ) → up stack"

if [[ $KEEP_DATA -eq 0 && $SKIP_CONFIRM -eq 0 ]]; then
  c_red ""
  c_red "⚠️  CẢNH BÁO: Sẽ XÓA SẠCH thư mục data/"
  c_red "    → Postgres DB, openclaw config, Zalo session, cache… sẽ MẤT"
  c_red "    → Nếu muốn giữ data: chạy lại với --keep-data"
  c_red "    → Bỏ qua xác nhận:    chạy với --yes / -y"
  c_yel ""
  c_yel "Bắt đầu sau 10 giây — Ctrl+C để HỦY..."
  for i in 10 9 8 7 6 5 4 3 2 1; do
    printf "\r    → %2d giây..." "$i"
    sleep 1
  done
  printf "\n\n"
fi

# ============================================================================
# 2. STOP + REMOVE CONTAINERS CŨ
# ============================================================================
step "2. Stop + remove containers cũ"
docker compose down -v --remove-orphans 2>&1 | sed 's/^/    /' || true

# Bonus: xoá container leftover nếu compose project name khác
for c in openclaw-gateway openclaw-postgres openclaw-cli; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    c_yel "    Xoá leftover container: $c"
    docker rm -f "$c" 2>/dev/null || true
  fi
done

# ============================================================================
# 3. XOÁ IMAGE CŨ + DANGLING
# ============================================================================
if [[ $KEEP_IMAGE -eq 0 ]]; then
  step "3. Xoá image cũ + dangling"
  if docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    docker rmi -f "$IMAGE_NAME" 2>&1 | sed 's/^/    /' || true
  else
    c_cyn "    ($IMAGE_NAME chưa có, bỏ qua)"
  fi
  # Xoá dangling images (build dở)
  DANGLING=$(docker images -f "dangling=true" -q 2>/dev/null | head -50)
  if [[ -n "$DANGLING" ]]; then
    c_yel "    Xoá $(echo "$DANGLING" | wc -l) dangling image(s)"
    docker rmi -f $DANGLING 2>/dev/null || true
  fi
else
  c_yel "3. Bỏ qua xoá image (--keep-image)"
fi

# ============================================================================
# 4. PRUNE BUILD CACHE
# ============================================================================
if [[ $KEEP_CACHE -eq 0 ]]; then
  step "4. Prune build cache + dangling volumes"
  docker builder prune -af 2>&1 | tail -3 | sed 's/^/    /' || true
  docker volume prune -f 2>&1 | tail -3 | sed 's/^/    /' || true
else
  c_yel "4. Bỏ qua prune cache (--keep-cache)"
fi

# ============================================================================
# 5. XOÁ data/ HOST
# ============================================================================
if [[ $KEEP_DATA -eq 0 ]]; then
  step "5. Xoá data/ host"
  if [[ -d data ]]; then
    BACKUP_HINT="data/ size: $(du -sh data 2>/dev/null | awk '{print $1}')"
    c_red "    🗑️  Xoá ($BACKUP_HINT)"
    $SUDO rm -rf data/ || rm -rf data/
  else
    c_cyn "    (data/ chưa có, bỏ qua)"
  fi
else
  c_yel "5. Bỏ qua xoá data/ (--keep-data)"
fi

# ============================================================================
# 6. ENSURE .env
# ============================================================================
step "6. .env"
if [[ ! -f .env ]]; then
  if [[ -f "$ENV_TEMPLATE" ]]; then
    cp "$ENV_TEMPLATE" .env
    c_grn "    ✓ .env tạo từ template: $ENV_TEMPLATE"
  else
    c_yel "    ⚠️  Tạo .env rỗng — bạn cần điền API keys sau!"
    : > .env
  fi
else
  c_cyn "    (.env đã có, giữ nguyên)"
fi

# ============================================================================
# 7. TẠO LẠI CẤU TRÚC data/
# ============================================================================
step "7. Tạo cấu trúc data/"
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

# ============================================================================
# 8. PERMISSION (postgres=999, openclaw=1000)
# ============================================================================
step "8. Set permission"
$SUDO chown -R 1000:1000 \
  data/openclaw data/workspace data/skills data/extensions \
  data/zalo data/logs data/hermes data/downloads data/projects \
  data/cache data/gemini data/gws data/claude 2>/dev/null || true
$SUDO chown -R 999:999 data/postgres 2>/dev/null || true
c_grn "    ✓ openclaw (1000:1000) + postgres (999:999)"

# ============================================================================
# 9. NETWORK
# ============================================================================
step "9. Network: $NETWORK_NAME"
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create "$NETWORK_NAME"
  c_grn "    ✓ Đã tạo network $NETWORK_NAME"
else
  c_cyn "    (network $NETWORK_NAME đã tồn tại)"
fi

# ============================================================================
# 10. BUILD
# ============================================================================
if [[ $DO_BUILD -eq 1 ]]; then
  if [[ $DO_LITE -eq 1 ]]; then
    step "10. Build $IMAGE_NAME (TEXLIVE_VARIANT=lite — ~10-15 phút)"
    DOCKER_BUILDKIT=1 TEXLIVE_VARIANT=lite \
      docker compose build --pull --no-cache openclaw-gateway
  else
    step "10. Build $IMAGE_NAME (TEXLIVE_VARIANT=full — 30-45 phút!)"
    DOCKER_BUILDKIT=1 \
      docker compose build --pull --no-cache openclaw-gateway
  fi
else
  c_yel "10. Bỏ qua build (--no-build)"
fi

# ============================================================================
# 11. PULL postgres
# ============================================================================
step "11. Pull postgres image"
docker compose pull postgres 2>&1 | tail -5 | sed 's/^/    /' || true

# ============================================================================
# 12. UP STACK
# ============================================================================
step "12. Up stack"
docker compose up -d postgres
sleep 4
docker compose up -d openclaw-gateway

c_grn ""
c_grn "✅ Stack đã chạy!"
echo ""
echo "    Theo dõi log:"
echo "        docker compose logs -f openclaw-gateway"
echo ""

# ============================================================================
# 13. ZALO LOGIN (tuỳ chọn)
# ============================================================================
if [[ $DO_ZALO -eq 1 ]]; then
  step "13. Login Zalo (entrypoint đã cài plugin openzalo)"
  c_cyn "    Đợi gateway boot 15s..."
  sleep 15
  c_yel "    → QR sắp hiện. Mở Zalo điện thoại → Quét."
  docker compose exec openclaw-gateway openclaw channels login --channel openzalo || \
    c_red "    ⚠️ Login fail — chạy thủ công sau: docker compose exec openclaw-gateway openclaw channels login --channel openzalo"

  cat <<EOF

$(c_grn "Sau khi quét QR:")
  1. docker compose restart openclaw-gateway
  2. Nhắn tin cho bot trên Zalo → lấy mã pairing → approve:
     docker compose exec openclaw-gateway \\
       openclaw pairing approve openzalo XXXXXXXX
EOF
fi

# ============================================================================
# 14. TỔNG KẾT
# ============================================================================
c_mag ""
c_mag "════════════════════════════════════════════════════════"
c_mag "                    ✅ HOÀN TẤT"
c_mag "════════════════════════════════════════════════════════"
cat <<EOF

$(c_grn "Cấu trúc data/:")
$(ls -la data/ 2>/dev/null | head -25)

$(c_grn "Lệnh hữu ích:")
  • Logs:           docker compose logs -f openclaw-gateway
  • Shell vào CLI:  docker compose --profile cli run --rm openclaw-cli bash
  • Plugins list:   docker compose exec openclaw-gateway openclaw plugins list
  • Restart GW:     docker compose restart openclaw-gateway
  • Update image:   docker compose build --pull && docker compose up -d
  • Cài lại sạch:   ./install.sh                  (XOÁ data + image cũ)
  • Cài giữ data:   ./install.sh --keep-data
  • Cài giữ tất cả: ./install.sh --soft           (= up lại)

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
