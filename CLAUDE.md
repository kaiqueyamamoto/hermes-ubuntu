# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## O que é

Imagem Docker Ubuntu 24.04 com Hermes Agent (Nous Research) rodando como root. O processo principal do container é o painel web (`hermes dashboard`, porta 9119). O CLI roda via `docker compose exec`. Não existe código de aplicação: o repo é só Dockerfile, scripts shell e smoke test.

## Comandos

```bash
make build            # docker compose build
make up               # sobe o container e espera o healthcheck (/api/status)
make test             # sobe e roda tests/smoke.sh dentro do container (suíte inteira)
make hermes | shell   # exec no container já rodando
docker compose up -d --build --wait && make test   # ciclo após editar Dockerfile/scripts
```

Um check isolado: `docker compose exec hermes /opt/hermes-tests/smoke.sh chrome_headless` (os argumentos são nomes de função em `tests/smoke.sh`). Os testes são copiados para a imagem (`/opt/hermes-tests`), então **rebuild antes de testar** qualquer mudança em `tests/`.

## Arquitetura (o que não é óbvio lendo um arquivo só)

- **Instalação do Hermes**: `install.sh` oficial rodando como root, que usa o layout FHS: código em `/usr/local/lib/hermes-agent` (venv próprio), comando em `/usr/local/bin/hermes`. Mas o node gerenciado, o `uv` e os dados ficam em `HERMES_HOME=/root/.hermes`.
- **Volume por cima de HERMES_HOME**: o volume `hermes-data` esconde o `/root/.hermes` da imagem. Por isso o build tira um snapshot em `/opt/hermes-seed`, e `scripts/entrypoint.sh`, a cada start: 1) copia o seed sem sobrescrever; 2) **substitui** `node/` e `bin/` pelos da imagem, para acompanharem o rebuild; 3) aplica `config/config.yaml` só no primeiro start (marker `.container-initialized`). Depois disso, a config é do usuário.
- **`docker exec` pula o entrypoint**: variável que o CLI precisa tem que ser `ENV` no Dockerfile, e não `export` no entrypoint. Foi por isso que `AGENT_BROWSER_EXECUTABLE_PATH` virou `ENV` apontando para o symlink `/usr/local/bin/chrome-bin`.
- **Navegador por arquitetura**: amd64 instala `google-chrome-stable`; arm64 usa o Chromium do Playwright em `/root/.cache/ms-playwright`. `scripts/chrome` resolve qual existe (`chrome --path`). Nunca usar Chromium via snap, porque o sandbox do snap quebra o agent-browser. O Hermes injeta `--no-sandbox` sozinho quando roda como root.
- **Painel web**: a UI é pré-compilada no build (`npm run build -w web` → `hermes_cli/web_dist`), e o runtime usa `--skip-build`. Bind em `0.0.0.0` exige um provider de auth desde jun/2026 (`--insecure` virou no-op). `scripts/dashboard.sh` usa o provider `basic` e gera senha e secret de sessão persistentes no volume (`dashboard-password`, `dashboard-secret`), a menos que venham do `.env`. O login é `POST /auth/password-login` com `{"provider":"basic","username","password"}`.
- **Terminal do agente**: `terminal.backend: local`, então os comandos do Hermes rodam no próprio container como root, com cwd `/workspace` (bind mount `./workspace`).
- `pip` do sistema liberado via `/etc/pip.conf` (`break-system-packages`), e as listas do apt são mantidas na imagem de propósito.

## Convenções do repo

- Versão em `VERSION` (semver). Faça o bump em toda mudança, no mesmo commit.
- Todo comportamento novo do container ganha uma função `check` em `tests/smoke.sh`.
