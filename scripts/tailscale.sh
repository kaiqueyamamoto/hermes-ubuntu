#!/usr/bin/env bash
# Conecta o container à tailnet no boot (modo userspace: sem NET_ADMIN nem
# /dev/net/tun). Conexões que chegam no IP 100.x são entregues às portas
# locais, então o painel/backend do Hermes (9119) fica acessível pela tailnet
# e o Hermes Desktop conecta em http://<TS_HOSTNAME>:9119.
#
# Liga quando TS_AUTHKEY está definido ou já existe estado salvo no volume.
# Nunca derruba o boot: se falhar, avisa e o painel sobe mesmo assim.
set -uo pipefail

STATE_DIR="${TS_STATE_DIR:-${HERMES_HOME:-/root/.hermes}/tailscale}"
SOCKET=/var/run/tailscale/tailscaled.sock
HOSTNAME_TS="${TS_HOSTNAME:-hermes}"

log() { echo "[tailscale] $*"; }

if [ -z "${TS_AUTHKEY:-}" ] && [ ! -s "$STATE_DIR/tailscaled.state" ]; then
    log "desligado (defina TS_AUTHKEY para entrar na tailnet)"
    exit 0
fi

mkdir -p "$STATE_DIR" /var/run/tailscale
tailscaled --tun=userspace-networking \
    --state="$STATE_DIR/tailscaled.state" \
    --socket="$SOCKET" \
    >>"$STATE_DIR/tailscaled.log" 2>&1 &

for _ in $(seq 1 50); do
    [ -S "$SOCKET" ] && break
    sleep 0.2
done

# shellcheck disable=SC2086
if ! timeout 60 tailscale up \
        ${TS_AUTHKEY:+--auth-key="$TS_AUTHKEY"} \
        --hostname="$HOSTNAME_TS" \
        ${TS_EXTRA_ARGS:-}; then
    log "falha no 'tailscale up' (chave inválida/expirada?). Log: $STATE_DIR/tailscaled.log"
    exit 0
fi

case "${TS_SERVE:-}" in
    1|true|TRUE|yes)
        # HTTPS com certificado da tailnet: https://<TS_HOSTNAME>.<tailnet>.ts.net
        if tailscale serve --bg --https=443 "http://127.0.0.1:${HERMES_DASHBOARD_PORT:-9119}" >/dev/null; then
            log "tailscale serve: https://$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')"
        else
            log "tailscale serve falhou (HTTPS habilitado na tailnet?)"
        fi
        ;;
esac

log "conectado: $(tailscale ip -4 | head -n1) ($HOSTNAME_TS) → Hermes Desktop: http://$HOSTNAME_TS:${HERMES_DASHBOARD_PORT:-9119}"
