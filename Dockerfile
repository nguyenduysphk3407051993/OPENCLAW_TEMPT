# syntax=docker/dockerfile:1.6
# =============================================================================
# OpenClaw SV-Pro — built on ghcr.io/openclaw/openclaw:latest
#  + TeXLive Full (chia 3 stage, retry → tránh exit 100)
#  + LibreOffice (bộ Office Linux)
#  + Office Python tools (docx/xlsx/pptx + image extract)
#  + PDF toolkit (split/merge/img↔pdf/OCR + rembg tách nền chất lượng cao)
#  + Video downloader đa nền tảng (yt-dlp + gallery-dl + you-get + streamlink)
#  + Dashboard (streamlit/dash/plotly/dtale/ydata-profiling)
#  + AI CLIs (Gemini, Codex, Claude Code, openzca)
#  + Plugins baked: openzalo, neural-memory, googleworkspace-cli, crawl4ai
#  + Camofox browser (Playwright bypass), Crawl4AI
#  + sudo NOPASSWD cho user openclaw → restart gateway/network từ container
# =============================================================================
FROM ghcr.io/openclaw/openclaw:latest

LABEL maintainer="OpenClaw Community"
LABEL description="OpenClaw SV-Pro — latest + LaTeX Full + LibreOffice + Office/PDF/Video/Dashboard + openzalo + GWS-CLI + neural-memory"
LABEL version="latest-sv-pro"

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
ENV NODE_ENV=production \
    PNPM_HOME="/pnpm" \
    PATH="/home/openclaw/.npm-global/bin:/pnpm:/usr/local/bin:$PATH" \
    TZ=Asia/Ho_Chi_Minh \
    NO_UPDATE_NOTIFIER=true \
    HOME=/home/openclaw \
    OPENCLAW_STATE_DIR=/home/openclaw/.openclaw \
    DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PIP_ROOT_USER_ACTION=ignore \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ============================================================================
# 0a. sudo SỚM để có /etc/sudoers.d/ (image official không có sudo)
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends sudo \
    && mkdir -p /etc/sudoers.d \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# 0b. Defensive user setup → đảm bảo có user `openclaw` UID 1000 + sudo NOPASSWD
# ============================================================================
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
    echo "[user] ✅ User setup done:"; id openclaw

# ============================================================================
# 1. SYSTEM DEPS — multimedia, PDF, fonts (Vi+CJK), OCR, locale, utilities
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    git git-lfs curl wget ca-certificates gnupg build-essential lsb-release \
    apt-utils apt-transport-https software-properties-common locales \
    python3 python3-pip python3-venv python3-dev python3-pygments \
    tzdata pandoc \
    poppler-utils ghostscript qpdf pdftk-java mupdf-tools img2pdf \
    fonts-noto fonts-noto-cjk fonts-noto-color-emoji \
    fonts-liberation fonts-dejavu fonts-lmodern \
    ffmpeg imagemagick mediainfo sox libsox-fmt-all atomicparsley aria2 \
    nano vim jq ripgrep fd-find tree htop \
    net-tools iputils-ping dnsutils iproute2 \
    unzip zip xz-utils bzip2 rsync openssh-client \
    gosu sudo tini \
    postgresql-client \
    tesseract-ocr tesseract-ocr-vie tesseract-ocr-eng \
    libgl1-mesa-glx libglib2.0-0 libsm6 libxext6 libxrender1 \
    libsndfile1 \
    libssl-dev libffi-dev libxml2-dev libxslt1-dev zlib1g-dev \
    libjpeg-dev libpng-dev libtiff-dev libwebp-dev \
    cmake pkg-config \
    hunspell hunspell-vi \
    && sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone \
    && ln -sf /usr/sbin/gosu /usr/local/bin/gosu \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# 1b. LIBREOFFICE — bộ Office Linux (Writer/Calc/Impress/Draw/Math)
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    libreoffice libreoffice-writer libreoffice-calc libreoffice-impress \
    libreoffice-draw libreoffice-math libreoffice-base \
    libreoffice-l10n-vi libreoffice-help-vi \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# 2. TEXLIVE — chia 3 stage + retry để tránh exit 100 (~5-6GB nếu full)
#    docker compose build --build-arg TEXLIVE_VARIANT=lite  → bỏ scheme-full
# ============================================================================
ARG TEXLIVE_VARIANT=full

# 2.1 Core + tools
RUN set -eux; \
    for i in 1 2 3; do \
      apt-get update && \
      apt-get install -y --no-install-recommends --fix-missing \
        texlive-base texlive-binaries \
        texlive-latex-base texlive-latex-recommended texlive-latex-extra \
        texlive-xetex texlive-luatex \
        latexmk biber chktex \
      && break || { echo "retry $i …"; apt-get clean; sleep 5; }; \
    done; \
    apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 2.2 Languages + fonts
RUN set -eux; \
    for i in 1 2 3; do \
      apt-get update && \
      apt-get install -y --no-install-recommends --fix-missing \
        texlive-lang-vietnamese texlive-lang-english texlive-lang-other \
        texlive-fonts-recommended texlive-fonts-extra \
      && break || { echo "retry $i …"; apt-get clean; sleep 5; }; \
    done; \
    apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 2.3 Science / publishers / pictures (chỉ khi VARIANT=full)
RUN set -eux; \
    if [ "${TEXLIVE_VARIANT}" = "full" ]; then \
      for i in 1 2 3; do \
        apt-get update && \
        apt-get install -y --no-install-recommends --fix-missing \
          texlive-science texlive-publishers texlive-pictures texlive-pstricks \
          texlive-music texlive-humanities texlive-games texlive-metapost \
          texlive-plain-generic \
        && break || { echo "retry $i …"; apt-get clean; sleep 5; }; \
      done; \
    else \
      echo "TEXLIVE_VARIANT=lite → bỏ scheme-full"; \
    fi; \
    apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ============================================================================
# 3. GLOBAL NPM TOOLS — Gemini, Codex, Claude Code, openzca, pnpm/yarn/pm2
# ============================================================================
RUN npm install -g \
        acpx@latest \
        @google/gemini-cli \
        @openai/codex \
        @anthropic-ai/claude-code \
        openzca \
        pnpm yarn pm2 ts-node typescript \
    && for bin in acpx gemini codex claude openzca pnpm yarn pm2 ts-node tsc; do \
         ln -sf "$(npm prefix -g)/bin/$bin" "/usr/local/bin/$bin" 2>/dev/null || true; \
       done \
    && npm cache clean --force

# ============================================================================
# 4. PYTHON STACK — Office, PDF, Dashboard, Video, BG-removal, Crawl4AI
# ============================================================================
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel

# 4.1 Office: docx/xlsx/pptx + image extraction
RUN python3 -m pip install --no-cache-dir \
      python-docx docx2txt mammoth \
      openpyxl xlsxwriter xlrd xlwt pyexcel pyexcel-xlsx \
      python-pptx pillow pypandoc

# 4.2 PDF: split/merge/img↔pdf/OCR
RUN python3 -m pip install --no-cache-dir \
      pypdf pdfplumber pdfminer.six pikepdf \
      pdf2image img2pdf reportlab ocrmypdf pymupdf

# 4.3 Background removal (PNG tách nền chất lượng cao)
RUN python3 -m pip install --no-cache-dir \
      "rembg[cpu]" onnxruntime backgroundremover

# 4.4 Video downloader đa nền tảng + bypass
RUN python3 -m pip install --no-cache-dir \
      yt-dlp gallery-dl you-get streamlink

# 4.5 Dashboard / phân tích Excel
RUN python3 -m pip install --no-cache-dir \
      pandas numpy scipy scikit-learn \
      matplotlib seaborn plotly bokeh altair \
      streamlit dash dash-bootstrap-components \
      panel holoviews hvplot \
      dtale ydata-profiling sweetviz \
      jupyterlab notebook ipywidgets

# 4.6 AI / API clients
RUN python3 -m pip install --no-cache-dir \
      requests httpx openai anthropic google-generativeai \
      python-dotenv tenacity rich typer click

# 4.7 Crawl4AI + Playwright (bypass anti-bot)
RUN python3 -m pip install --no-cache-dir \
      git+https://github.com/unclecode/crawl4ai.git \
    && python3 -m playwright install-deps chromium \
    && python3 -m playwright install chromium \
    && rm -rf /tmp/playwright* /root/.cache/pip

# ============================================================================
# 4a. CLONE REPOS vào /opt/repos-seed/ (baked vào image)
# ============================================================================
RUN mkdir -p /opt/repos-seed

# neural-memory
RUN git clone --depth 1 https://github.com/nhadaututtheky/neural-memory.git \
    /opt/repos-seed/neural-memory || echo "neural-memory clone fail"

# Google Workspace CLI
RUN git clone --depth 1 https://github.com/googleworkspace/cli.git \
    /opt/repos-seed/googleworkspace-cli \
    && if [ -f /opt/repos-seed/googleworkspace-cli/package.json ]; then \
           npm install --prefix /opt/repos-seed/googleworkspace-cli --ignore-scripts || true; \
       fi

# Camofox browser (Playwright bypass)
RUN git clone --depth 1 https://github.com/jo-inc/camofox-browser.git \
    /opt/repos-seed/camofox-browser 2>/dev/null \
    && if [ -f /opt/repos-seed/camofox-browser/requirements.txt ]; then \
           pip3 install --no-cache-dir --break-system-packages \
               -r /opt/repos-seed/camofox-browser/requirements.txt 2>&1 | tail -5 || true; \
       fi \
    || echo "camofox-browser repo unavailable, skipping"

# Crawl4AI source
RUN git clone --depth 1 https://github.com/unclecode/crawl4ai.git \
    /opt/repos-seed/crawl4ai || echo "crawl4ai clone fail"

# OpenZalo plugin
RUN git clone --depth 1 https://github.com/darkamenosa/openzalo.git \
    /opt/repos-seed/openzalo \
    && if [ -f /opt/repos-seed/openzalo/package.json ]; then \
           npm install --prefix /opt/repos-seed/openzalo --no-audit --no-fund --ignore-scripts || true; \
       fi

RUN mkdir -p /opt/neural-memory /opt/googleworkspace-cli /opt/camofox-browser /opt/crawl4ai \
    && chown -R root:root /opt/repos-seed

# ============================================================================
# 4b. Pre-warm rembg model (best-effort)
# ============================================================================
RUN sudo -u openclaw bash -c 'mkdir -p ~/.u2net && rembg d u2net' 2>/dev/null || true

# ============================================================================
# 4c. PATH login shell + openclaw shim
# ============================================================================
RUN printf '%s\n' \
    '# OpenClaw SV — giữ PATH đúng trong mọi login shell context' \
    'export PATH="/home/openclaw/.npm-global/bin:/pnpm:/usr/local/bin:${PATH}"' \
    'export PNPM_HOME="/pnpm"' \
    'export NODE_ENV=production' \
    'export OPENCLAW_STATE_DIR=/home/openclaw/.openclaw' \
    'export HOME=/home/openclaw' \
    > /etc/profile.d/openclaw-path.sh \
    && sed -i 's/\r$//' /etc/profile.d/openclaw-path.sh \
    && chmod +x /etc/profile.d/openclaw-path.sh

RUN printf '#!/bin/sh\nexec node /app/dist/index.js "$@"\n' \
        > /usr/local/bin/openclaw \
    && chmod +x /usr/local/bin/openclaw

# ============================================================================
# 5. Permissions /app — fix EACCES cho user openclaw đọc node_modules
# ============================================================================
RUN chmod -R go+rX /app 2>/dev/null || true \
    && find /app -type d -exec chmod a+rx {} \; 2>/dev/null || true \
    && find /app -type f -exec chmod a+r {} \; 2>/dev/null || true

# ============================================================================
# 6. HELPER SCRIPTS — install-pkg / install-pip / install-npm runtime
# ============================================================================
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

# ============================================================================
# 7. ENTRYPOINT — 6-step OpenZalo install + restore repos + plugin seeding
# ============================================================================
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh && chmod +x /usr/local/bin/entrypoint.sh

# ============================================================================
# 8. Healthcheck & runtime
# ============================================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD curl -sf http://localhost:18789/health || exit 1

STOPSIGNAL SIGTERM
WORKDIR /home/openclaw/.openclaw/workspace
EXPOSE 18789

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["gateway", "--bind", "lan"]
