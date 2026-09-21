# syntax=docker/dockerfile:1
#
# Ubuntu 24.04 com Hermes Agent rodando como root.
# O agente pode: apt update/install, criar e executar scripts Python,
# acessar a internet e controlar um Chrome/Chromium headless.

FROM ubuntu:24.04

ARG TARGETARCH
ARG HERMES_INSTALL_URL=https://hermes-agent.nousresearch.com/install.sh

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=America/Sao_Paulo \
    HERMES_HOME=/root/.hermes \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    NODE_PATH=/usr/local/lib/node_modules \
    PYTHONUNBUFFERED=1 \
    PATH=/root/.hermes/node/bin:/root/.hermes/bin:/root/.local/bin:$PATH

# Pacotes base: Python completo (pip/venv), build tools e utilitários de rede.
# As listas do apt NÃO são apagadas: o agente pode instalar pacotes de imediato.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg git xz-utils unzip \
        build-essential pkg-config \
        python3 python3-pip python3-venv python3-dev python-is-python3 \
        sudo nano less procps tini tzdata jq \
        xvfb xauth \
        iputils-ping dnsutils net-tools \
        fonts-liberation fonts-noto-color-emoji \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

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
