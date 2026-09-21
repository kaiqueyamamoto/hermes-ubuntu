#!/usr/bin/env bash
# Sobe o painel web do Hermes em foreground (processo principal do container).
# Bind fora do loopback exige auth: usamos o provider basic (usuário/senha).
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
PASS_FILE="$HERMES_HOME/dashboard-password"

export HERMES_DASHBOARD_BASIC_AUTH_USERNAME="${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-admin}"

if [ -z "${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:-}" ] && [ -z "${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH:-}" ]; then
    if [ ! -s "$PASS_FILE" ]; then
        (umask 077 && python3 -c 'import secrets; print(secrets.token_urlsafe(18))' > "$PASS_FILE")
        echo "[dashboard] senha gerada e salva em $PASS_FILE"
    fi
    HERMES_DASHBOARD_BASIC_AUTH_PASSWORD="$(cat "$PASS_FILE")"
    export HERMES_DASHBOARD_BASIC_AUTH_PASSWORD
fi

# Segredo de sessão estável: logins sobrevivem a restart do container.
SECRET_FILE="$HERMES_HOME/dashboard-secret"
if [ -z "${HERMES_DASHBOARD_BASIC_AUTH_SECRET:-}" ]; then
    [ -s "$SECRET_FILE" ] || (umask 077 && python3 -c 'import secrets; print(secrets.token_hex(32))' > "$SECRET_FILE")
    HERMES_DASHBOARD_BASIC_AUTH_SECRET="$(cat "$SECRET_FILE")"
    export HERMES_DASHBOARD_BASIC_AUTH_SECRET
fi

host="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
port="${HERMES_DASHBOARD_PORT:-9119}"
echo "[dashboard] http://localhost:$port  usuário: $HERMES_DASHBOARD_BASIC_AUTH_USERNAME"

cd /workspace
exec hermes dashboard --host "$host" --port "$port" --no-open "$@"
