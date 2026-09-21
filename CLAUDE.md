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
- **Playwright**: `PLAYWRIGHT_BROWSERS_PATH=/ms-playwright` fica fora do volume. O Playwright Python (pip) e o Node (`npm -g`, resolvido via `NODE_PATH=/usr/local/lib/node_modules`) são instalados na versão exata do `npx playwright` do Hermes, para compartilharem a mesma revisão do Chromium. O `npm -g` vem antes do `pip`, porque os dois gravam `/usr/local/bin/playwright` e o que fica deve ser o do Python. Exemplos em `examples/` são copiados para `/opt/hermes-examples` e rodados pelo smoke test.
- **A imagem roda sem compose** (`docker run` puro também passa no smoke test). Não coloque no compose nada de que a imagem precise para funcionar.
- **Navegador por arquitetura**: amd64 instala `google-chrome-stable`; arm64 usa o Chromium do Playwright em `/ms-playwright`. `scripts/chrome` resolve qual existe (`chrome --path`). Nunca usar Chromium via snap, porque o sandbox do snap quebra o agent-browser. O Hermes injeta `--no-sandbox` sozinho quando roda como root.
- **Painel web**: a UI é pré-compilada no build (`npm run build -w web` → `hermes_cli/web_dist`), e o runtime usa `--skip-build`. Bind em `0.0.0.0` exige um provider de auth desde jun/2026 (`--insecure` virou no-op). `scripts/dashboard.sh` usa o provider `basic` e gera senha e secret de sessão persistentes no volume (`dashboard-password`, `dashboard-secret`), a menos que venham do `.env`. O login é `POST /auth/password-login` com `{"provider":"basic","username","password"}`.
- **Tailscale**: `scripts/tailscale.sh` (`hermes-tailscale`) é chamado pelo entrypoint antes do comando principal. Ele só liga com `TS_AUTHKEY` ou com estado salvo em `$HERMES_HOME/tailscale`. Roda `tailscaled --tun=userspace-networking`: sem TUN, o netstack entrega conexões do IP 100.x às portas locais, e por isso o painel em `0.0.0.0:9119` responde na tailnet. Qualquer falha precisa sair com 0, porque Tailscale nunca pode bloquear o boot do painel.
- **Hermes Desktop**: conecta no backend JSON-RPC/WebSocket. `hermes dashboard` é o mesmo servidor de `hermes serve`, mais a UI, então a porta 9119 serve os dois e usa a mesma auth basic. O guard de Host aceita IP 100.x e nomes MagicDNS sem configuração extra.
- **SQLite**: o estágio `sqlite_build` compila a mesma versão e as mesmas flags da imagem oficial. A lib fica em `/opt/sqlite-fixed/lib`, registrada em `/etc/ld.so.conf.d/00-sqlite-fixed.conf`. Precisa ser `00-`: em `/usr/local/lib` perde para `/lib/<arch>` no ldconfig e o Python continua com o 3.45.1, que tem o bug de WAL-reset.
- **Extras do Hermes** entram por `uv pip install -e ".[...]"` no venv de `/usr/local/lib/hermes-agent`. `HERMES_LAZY_INSTALL_TARGET` aponta para o volume, e sem isso os lazy installs somem quando o container é recriado. O entrypoint roda `hermes config migrate </dev/null` a cada boot (é idempotente), porque o `config.yaml` semeado não tem `_config_version`.
- `hermes doctor` sem nenhum `✗` é um check do smoke test. Um `⚠` por falta de API key é esperado.
- **Terminal do agente**: `terminal.backend: local`, então os comandos do Hermes rodam no próprio container como root, com cwd `/workspace` (bind mount `./workspace`).
- `pip` do sistema liberado via `/etc/pip.conf` (`break-system-packages`), e as listas do apt são mantidas na imagem de propósito.

## Convenções do repo

- Versão em `VERSION` (semver). Faça o bump em toda mudança, no mesmo commit.
- Todo comportamento novo do container ganha uma função `check` em `tests/smoke.sh`.
