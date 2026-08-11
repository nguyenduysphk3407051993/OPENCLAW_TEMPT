# ==========================================================================
# Custom layer trên prebuilt OpenClaw image
# - Upstream đã build sẵn OpenClaw → không cần pnpm build:docker (né OOM)
# - User `node` cố định (UID 1000) - không thay đổi được, đúng convention
# - Plugin openzalo hardcode /home/node/.npm-global/lib/node_modules/openzca/...
#   → npm install -g với user node tự khớp path, không cần symlink hack
# ==========================================================================
ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:latest
FROM ${OPENCLAW_BASE_IMAGE}

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

RUN apt-get update     && apt-get install -y --no-install-recommends         python3         python3-pip         python3-venv         ca-certificates         curl         texlive-full         tesseract-ocr         tesseract-ocr-vie         tesseract-ocr-eng         chromium         ffmpeg         pandoc         poppler-utils         ghostscript         fonts-noto         build-essential         python3-dev         libffi-dev         sudo     && echo "node ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/node     && chmod 0440 /etc/sudoers.d/node     && rm -rf /var/lib/apt/lists/*     && echo "✅ System deps installed"     && python3 -m pip install --no-cache-dir --break-system-packages --upgrade         pip         setuptools         wheel     && python3 -m pip install --no-cache-dir --break-system-packages         --prefer-binary         --timeout 120         --retries 5         yt-dlp         mutagen         brotli         websockets         pycryptodomex     && if ! python3 -m pip install --no-cache-dir --break-system-packages         --prefer-binary         --timeout 120         --retries 5         curl-cffi; then         echo "⚠️ curl-cffi not available, yt-dlp will use fallback";     fi     && python3 -m yt_dlp --version     && echo "✅ yt-dlp layer OK"

# ==========================================================================
# 📦 Layer 2: NPM globals (user node) - openzca + acpx + gemini
# Cài vào /home/node/.npm-global/lib/node_modules/<pkg> - đúng path plugin
# ==========================================================================
ENV PATH="/home/node/.npm-global/bin:${PATH}"
USER node
RUN mkdir -p /home/node/.npm-global \
    && npm config set prefix /home/node/.npm-global \
    && (npm install -g --no-fund --no-audit openzca acpx @google/gemini-cli || \
        (echo "⚠️ Retry with --unsafe-perm..." && npm install -g --no-fund --no-audit --unsafe-perm openzca acpx @google/gemini-cli)) \
    && npm cache clean --force \
    && ls -la /home/node/.npm-global/lib/node_modules/openzca \
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
