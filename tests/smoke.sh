#!/usr/bin/env bash
# Smoke test: valida dentro do container cada capacidade que o Hermes precisa.
# Uso: make test   (ou docker compose exec hermes /opt/hermes-tests/smoke.sh [funcao...])
# Com argumentos, roda só as funções nomeadas (ex.: smoke.sh chrome_headless).
set -uo pipefail

PASS=0
FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

check() {
    local name="$1"; shift
    if out="$("$@" 2>&1)"; then
        echo "ok   - $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL - $name"
        echo "$out" | tail -n 15 | sed 's/^/       /'
        FAIL=$((FAIL + 1))
    fi
}

is_root() { [ "$(id -u)" -eq 0 ]; }

apt_update() { apt-get update -qq; }

apt_install() {
    apt-get install -y -qq --no-install-recommends cowsay >/dev/null \
        && [ -x /usr/games/cowsay ]
}

python_create_and_run() {
    cat > "$TMP/soma.py" <<'PY'
import sys
print(sum(int(a) for a in sys.argv[1:]))
PY
    [ "$(python3 "$TMP/soma.py" 2 3 5)" = "10" ]
}

python_venv_pip() {
    python3 -m venv "$TMP/venv" \
        && "$TMP/venv/bin/pip" install -q six \
        && "$TMP/venv/bin/python" -c 'import six'
}

pip_system() { pip install -q --no-input six && python3 -c 'import six'; }

internet_https() { curl -fsS --max-time 20 -o /dev/null https://example.com; }

dns_resolve() { getent hosts pypi.org >/dev/null; }

chrome_headless() {
    chrome --headless=new --disable-gpu --dump-dom https://example.com 2>/dev/null \
        | grep -q "Example Domain"
}

hermes_browser_driver() {
    local title
    cd "$TMP" || return 1
    timeout 180 npx -y agent-browser open https://example.com >/dev/null || return 1
    title="$(timeout 30 npx -y agent-browser get title)"
    npx -y agent-browser close >/dev/null 2>&1 || true
    echo "$title" | grep -q "Example Domain"
}

playwright_python() {
    [ "$(python3 /opt/hermes-examples/playwright_exemplo.py https://example.com)" = "Example Domain" ]
}

playwright_python_headed_xvfb() {
    [ "$(xvfb-run -a python3 /opt/hermes-examples/playwright_exemplo.py https://example.com --headed)" = "Example Domain" ]
}

playwright_node() {
    cd "$TMP" || return 1
    [ "$(node /opt/hermes-examples/playwright_exemplo.mjs https://example.com)" = "Example Domain" ]
}

playwright_same_version() {
    local py node
    py="$(python3 -c 'from importlib.metadata import version; print(version("playwright"))')"
    node="$(node -p 'require("playwright/package.json").version')"
    [ "$py" = "$node" ] || { echo "python=$py node=$node"; return 1; }
}

hermes_cli() { hermes --version; }

hermes_home_writable() {
    touch "$HERMES_HOME/.smoke" && rm "$HERMES_HOME/.smoke"
}

hermes_terminal_local() {
    grep -Eq '^\s*backend:\s*local' "$HERMES_HOME/config.yaml"
}

hermes_browser_points_to_chrome() {
    [ -n "${AGENT_BROWSER_EXECUTABLE_PATH:-}" ] && [ -x "$AGENT_BROWSER_EXECUTABLE_PATH" ]
}

dashboard_up() {
    local port="${HERMES_DASHBOARD_PORT:-9119}"
    curl -fsS --max-time 5 -o /dev/null "http://127.0.0.1:$port/"
}

dashboard_requires_auth() {
    local port="${HERMES_DASHBOARD_PORT:-9119}" code
    code="$(curl -s --max-time 5 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/api/config")"
    [ "$code" = "401" ] || [ "$code" = "403" ] || { echo "HTTP $code sem login"; return 1; }
}

dashboard_login() {
    local port="${HERMES_DASHBOARD_PORT:-9119}" user pw jar="$TMP/cookies"
    user="${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-admin}"
    pw="${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:-$(cat "$HERMES_HOME/dashboard-password")}"
    login() {
        python3 -c 'import json,sys; print(json.dumps({"provider":"basic","username":sys.argv[1],"password":sys.argv[2]}))' "$1" "$2" \
            | curl -s -o /dev/null -w '%{http_code}' -c "$jar" -H 'content-type: application/json' \
                --data-binary @- "http://127.0.0.1:$port/auth/password-login"
    }
    [ "$(login "$user" "senha-errada")" = "401" ] || { echo "senha errada não deu 401"; return 1; }
    [ "$(login "$user" "$pw")" = "200" ] || { echo "login válido falhou"; return 1; }
    [ "$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" "http://127.0.0.1:$port/api/config")" = "200" ]
}

if [ $# -gt 0 ]; then
    for fn in "$@"; do check "$fn" "$fn"; done
    echo; echo "$PASS ok, $FAIL falha(s)"
    [ "$FAIL" -eq 0 ]; exit
fi

tailscale_installed() { tailscale version >/dev/null && command -v tailscaled >/dev/null; }

tailscale_state() {
    # Sem TS_AUTHKEY: não sobe e não pode atrapalhar o boot.
    # Com TS_AUTHKEY: precisa estar conectado na tailnet.
    if [ -z "${TS_AUTHKEY:-}" ]; then
        ! pgrep -x tailscaled >/dev/null || { echo "tailscaled rodando sem TS_AUTHKEY"; return 1; }
        return 0
    fi
    [ "$(tailscale status --json | jq -r .BackendState)" = "Running" ]
}

check "roda como root"                          is_root
check "apt-get update"                          apt_update
check "apt-get install (cowsay)"                apt_install
check "cria e executa script Python"            python_create_and_run
check "venv + pip install"                      python_venv_pip
check "pip install no Python do sistema"        pip_system
check "resolve DNS"                             dns_resolve
check "acessa internet via HTTPS"               internet_https
check "Chrome headless renderiza página"        chrome_headless
check "Playwright Python (headless)"            playwright_python
check "Playwright Python headed via xvfb-run"   playwright_python_headed_xvfb
check "Playwright Node"                         playwright_node
check "Playwright Python e Node mesma versão"   playwright_same_version
check "Tailscale instalado"                     tailscale_installed
check "Tailscale conforme TS_AUTHKEY"           tailscale_state
check "hermes CLI instalado"                    hermes_cli
check "HERMES_HOME gravável"                    hermes_home_writable
check "terminal do Hermes em modo local"        hermes_terminal_local
check "browser do Hermes aponta pro Chrome"     hermes_browser_points_to_chrome
check "agent-browser (driver do Hermes) navega" hermes_browser_driver
check "painel web no ar desde o boot"           dashboard_up
check "painel web exige login"                  dashboard_requires_auth
check "login no painel com usuário/senha"       dashboard_login

echo
echo "$PASS ok, $FAIL falha(s)"
[ "$FAIL" -eq 0 ]
