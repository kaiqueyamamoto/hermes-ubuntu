# syntax=docker/dockerfile:1
#
# Ubuntu 24.04 com Hermes Agent rodando como root.
# O agente pode: apt update/install, criar e executar scripts Python,
# acessar a internet e controlar um Chrome/Chromium headless.

# SQLite do Ubuntu 24.04 (3.45.1) tem o bug de WAL-reset que pode corromper o
# state.db do Hermes (https://sqlite.org/wal.html#walresetbug). Compilamos a
# mesma versão/flags da imagem oficial e ela passa a ter precedência no loader.
FROM ubuntu:24.04 AS sqlite_build
ARG SQLITE_AUTOCONF_VERSION=3530400
ARG SQLITE_SHA256=0e9483900e92cd5de8fd48d16bf9200145a61f7fd5be542a5ac81d8a9516eb9c
RUN apt-get update && apt-get install -y --no-install-recommends build-essential ca-certificates curl \
    && curl -fsSL --retry 3 -o /tmp/sqlite.tar.gz \
        "https://sqlite.org/2026/sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}.tar.gz" \
    && echo "${SQLITE_SHA256}  /tmp/sqlite.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/sqlite.tar.gz -C /tmp \
    && cd "/tmp/sqlite-autoconf-${SQLITE_AUTOCONF_VERSION}" \
    && CFLAGS="-O2 -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS4 \
        -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_GEOPOLY \
        -DSQLITE_ENABLE_COLUMN_METADATA -DSQLITE_ENABLE_UNLOCK_NOTIFY -DSQLITE_ENABLE_DBSTAT_VTAB \
        -DSQLITE_ENABLE_DBPAGE_VTAB -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_PREUPDATE_HOOK \
        -DSQLITE_ENABLE_SESSION -DSQLITE_SECURE_DELETE -DSQLITE_THREADSAFE=1 \
        -DSQLITE_MAX_VARIABLE_NUMBER=250000" \
        ./configure --prefix=/opt/sqlite-fixed --disable-static \
    && make -j"$(nproc)" && make install

FROM ubuntu:24.04

ARG TARGETARCH
# false = sem Claude Code/Codex CLI (~540MB a menos)
ARG INSTALL_AGENT_CLIS=true
ARG HERMES_INSTALL_URL=https://hermes-agent.nousresearch.com/install.sh

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=America/Sao_Paulo \
    HERMES_HOME=/root/.hermes \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    NODE_PATH=/usr/local/lib/node_modules \
    PYTHONUNBUFFERED=1 \
    HERMES_LAZY_INSTALL_TARGET=/root/.hermes/lazy-packages \
    PATH=/root/.hermes/node/bin:/root/.hermes/bin:/root/.local/bin:$PATH

# Pacotes base: Python completo (pip/venv), build tools e utilitários de rede.
# As listas do apt NÃO são apagadas: o agente pode instalar pacotes de imediato.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg git xz-utils unzip \
        build-essential pkg-config \
        python3 python3-pip python3-venv python3-dev python-is-python3 \
        sudo nano less procps tini tzdata jq \
        xvfb xauth \
        openssh-client sqlite3 tmux rsync zip ripgrep ffmpeg \
        cmake libffi-dev libolm-dev libopus0 libportaudio2 \
        iputils-ping dnsutils net-tools \
        fonts-liberation fonts-noto-color-emoji \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# SQLite corrigido na frente do da distro (Python do Hermes, do sistema e CLI).
# Diretório próprio + conf "00-" para vencer /lib/<arch> na ordem do ldconfig.
COPY --from=sqlite_build /opt/sqlite-fixed/ /opt/sqlite-fixed/
RUN echo /opt/sqlite-fixed/lib > /etc/ld.so.conf.d/00-sqlite-fixed.conf \
    && ln -sf /opt/sqlite-fixed/bin/sqlite3 /usr/local/bin/sqlite3 \
    && ldconfig && python3 -c "import sqlite3,sys; v=sqlite3.sqlite_version; print('SQLite', v); sys.exit(v < '3.51.3')"

# GitHub CLI (usado pelas skills github/codex e para o agente operar repositórios).
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh

# pip do sistema liberado para root (Ubuntu 24.04 bloqueia por padrão via PEP 668).
RUN printf '[global]\nbreak-system-packages = true\nroot-user-action = ignore\n' > /etc/pip.conf

# Google Chrome só existe para amd64. Em arm64 (Apple Silicon) usamos o
# Chromium do Playwright, que o instalador do Hermes já baixa.
RUN if [ "$TARGETARCH" = "amd64" ]; then \
        curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
            | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
        && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
            > /etc/apt/sources.list.d/google-chrome.list \
        && apt-get update && apt-get install -y --no-install-recommends google-chrome-stable; \
    fi

# Tailscale (repo oficial). Sobe no boot em modo userspace quando TS_AUTHKEY
# está definido: o container aparece na tailnet sem precisar de NET_ADMIN.
RUN curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg \
    && curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
        -o /etc/apt/sources.list.d/tailscale.list \
    && apt-get update && apt-get install -y --no-install-recommends tailscale \
    && tailscale version

# Hermes Agent (modo root: código em /usr/local/lib/hermes-agent,
# comando em /usr/local/bin/hermes, dados em $HERMES_HOME).
# --with-deps do Playwright instala as libs de sistema do Chromium.
RUN curl -fsSL "$HERMES_INSTALL_URL" -o /tmp/hermes-install.sh \
    && bash /tmp/hermes-install.sh --skip-setup --non-interactive --skip-computer-use \
    && rm -f /tmp/hermes-install.sh \
    && hermes --version

# Playwright para scripts do usuário, em Python e Node, na MESMA versão do
# Playwright do Hermes: todos usam o mesmo Chromium em $PLAYWRIGHT_BROWSERS_PATH.
# O pip vem depois do npm para o comando `playwright` no PATH ser o do Python.
RUN PW_VERSION="$(cd /usr/local/lib/hermes-agent && npx playwright --version | awk '{print $2}')" \
    && echo "Playwright $PW_VERSION" \
    && npm install -g --no-audit --no-fund "playwright@$PW_VERSION" \
    && pip install --no-cache-dir "playwright==$PW_VERSION" \
    && python3 -m playwright install --with-deps chromium \
    && python3 -c "import playwright" \
    && node -e "require('playwright')"

# Painel web pré-compilado na imagem: o boot não depende de npm/rede.
RUN cd /usr/local/lib/hermes-agent \
    && npm install --workspace web --no-audit --no-fund \
    && npm run build -w web \
    && test -f hermes_cli/web_dist/index.html

# Extras do Hermes que a imagem oficial instala (mensageria, provedores, matrix,
# observabilidade) + google (skill google-workspace) + voice (STT local com
# faster-whisper para áudios recebidos). Resto é lazy-install, persistido no volume.
RUN cd /usr/local/lib/hermes-agent \
    && uv pip install --python venv/bin/python -e \
        ".[messaging,anthropic,bedrock,azure-identity,hindsight,matrix,google-chat,otlp,google,voice,edge-tts]" \
    && venv/bin/python -c "import telegram, discord, slack_bolt, anthropic, faster_whisper, mautrix, googleapiclient, edge_tts"

# Dependências das skills que vêm com o Hermes.
#   Python: docx/xlsx/powerpoint, codebase-inspection, youtube-content
#   CLIs:   himalaya (email), xurl (X/Twitter), claude-code e codex (agentes)
RUN pip install --no-cache-dir python-docx openpyxl python-pptx pygount youtube-transcript-api \
    && npm install -g --no-audit --no-fund @xdevplatform/xurl \
    && curl -fsSL https://raw.githubusercontent.com/pimalaya/himalaya/master/install.sh | PREFIX=/usr/local sh \
    && himalaya --version && xurl --help >/dev/null
RUN if [ "$INSTALL_AGENT_CLIS" = "true" ]; then \
        npm install -g --no-audit --no-fund @anthropic-ai/claude-code @openai/codex \
        && claude --version && codex --version; \
    fi

COPY scripts/chrome /usr/local/bin/chrome
COPY scripts/entrypoint.sh /usr/local/bin/hermes-entrypoint
COPY scripts/dashboard.sh /usr/local/bin/hermes-dashboard
COPY scripts/tailscale.sh /usr/local/bin/hermes-tailscale
COPY config/config.yaml /opt/hermes-defaults/config.yaml
COPY tests /opt/hermes-tests
COPY examples /opt/hermes-examples

# Snapshot do HERMES_HOME da imagem. O volume persistente é montado por cima
# de /root/.hermes; o entrypoint semeia o volume e atualiza node/ e bin/.
RUN chmod +x /usr/local/bin/chrome /usr/local/bin/hermes-entrypoint /usr/local/bin/hermes-dashboard /usr/local/bin/hermes-tailscale /opt/hermes-tests/*.sh \
    && ln -s "$(chrome --path)" /usr/local/bin/chrome-bin \
    && mkdir -p /root/.local/bin && ln -sf /usr/local/bin/hermes /root/.local/bin/hermes \
    && cp -a /root/.hermes /opt/hermes-seed

# Browser tool do Hermes usa o Chrome/Chromium da imagem (vale também para
# `docker exec`, que não passa pelo entrypoint). --no-sandbox o Hermes injeta
# sozinho quando roda como root.
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/local/bin/chrome-bin

WORKDIR /workspace
VOLUME ["/root/.hermes"]
EXPOSE 9119

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS -o /dev/null http://127.0.0.1:${HERMES_DASHBOARD_PORT:-9119}/api/status || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hermes-entrypoint"]
# Boot padrão: painel web ligado. Para o CLI: docker compose exec hermes hermes
CMD ["hermes-dashboard", "--skip-build"]
