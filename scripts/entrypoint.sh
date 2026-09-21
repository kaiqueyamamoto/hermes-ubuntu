#!/usr/bin/env bash
# Prepara o HERMES_HOME persistente e executa o comando pedido.
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
SEED=/opt/hermes-seed
mkdir -p "$HERMES_HOME"

# Primeiro start: copia o estado inicial da imagem para o volume (sem sobrescrever).
cp -a --update=none "$SEED/." "$HERMES_HOME/"

# Runtime gerenciado pela imagem (node, uv): sempre acompanha a versão da imagem.
for dir in node bin; do
    if [ -d "$SEED/$dir" ]; then
        rm -rf "${HERMES_HOME:?}/$dir"
        cp -a "$SEED/$dir" "$HERMES_HOME/$dir"
    fi
done

# Config padrão do container aplicada uma única vez; depois o usuário manda.
if [ ! -f "$HERMES_HOME/.container-initialized" ]; then
    cp /opt/hermes-defaults/config.yaml "$HERMES_HOME/config.yaml"
    touch "$HERMES_HOME/.container-initialized"
fi

exec "$@"
