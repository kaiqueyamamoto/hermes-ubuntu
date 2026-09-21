# ubuntu-hermes

Container Ubuntu 24.04 com o [Hermes Agent](https://hermes-agent.nousresearch.com) rodando como **root**, e o painel web ligado desde o boot.

Dentro do container o agente pode:

- atualizar e instalar pacotes (`apt-get update` / `apt-get install`)
- criar e executar scripts Python (`python3`, `pip`, `venv`)
- acessar a internet normalmente
- controlar um navegador: Google Chrome no amd64, Chromium do Playwright no arm64 (Apple Silicon). O Google Chrome não tem build para Linux arm64.

## Playwright e scripts

O Playwright vem pronto em **Python** e em **Node**, na mesma versão do Playwright interno do Hermes, e os três usam o mesmo Chromium em `/ms-playwright`. Rodando como root, o Playwright já desliga o sandbox sozinho.

```bash
python3 /opt/hermes-examples/playwright_exemplo.py https://example.com
xvfb-run -a python3 /opt/hermes-examples/playwright_exemplo.py --headed   # navegador "visível" num display virtual
node /opt/hermes-examples/playwright_exemplo.mjs https://example.com
```

Em Node, `require("playwright")` funciona de qualquer pasta (`NODE_PATH`). Em ESM, use `createRequire`, como no exemplo.

## O que vem instalado

Os extras são os mesmos da imagem oficial do Hermes, mais o que as skills incluídas precisam:

| Área | Conteúdo |
|------|----------|
| Hermes (extras Python) | mensageria (Telegram, Discord, Slack, Matrix, Google Chat), provedores (Anthropic, Bedrock, Azure), Google Workspace, voz (faster-whisper STT local, edge-tts), OTLP, Hindsight |
| Sistema | SQLite 3.53.4 compilado (o 3.45.1 do Ubuntu tem o bug de WAL-reset), ffmpeg, ripgrep, openssh-client, tmux, rsync, gh, libopus/portaudio |
| Skills | himalaya (email), xurl (X), python-docx/openpyxl/python-pptx, pygount, youtube-transcript-api, Claude Code e Codex CLI |

- Pacotes instalados sob demanda (lazy installs) ficam em `/root/.hermes/lazy-packages`, no volume, e sobrevivem a rebuilds.
- `docker build --build-arg INSTALL_AGENT_CLIS=false` deixa de fora o Claude Code e o Codex (cerca de 540 MB a menos).

**Fora da imagem, de propósito:**
- `computer_use`: exige cua-driver, um desktop X/Xvfb e AT-SPI.
- Backend de terminal `docker`: exigiria montar o socket do host.
- Manim + LaTeX: vários GB.
- songsee: requer o toolchain Go.
- Skills da Apple: só funcionam no macOS.

O agente é root e tem internet, então consegue instalar qualquer um desses quando precisar.

**Chaves que liberam mais ferramentas** (`.env` ou `hermes setup`): provedor do modelo (também habilita vision e video), `FAL_KEY` (image_gen), `EXA_API_KEY`/`FIRECRAWL_API_KEY` (busca web), `XAI_API_KEY`, `HASS_TOKEN`, `GITHUB_TOKEN` (Skills Hub sem rate limit).

## Tailscale + Hermes Desktop

Com `TS_AUTHKEY` definido, o container entra na sua tailnet assim que inicia, com o nome `TS_HOSTNAME` (padrão `hermes`). O Tailscale roda em modo userspace, então não precisa de `--cap-add NET_ADMIN` nem de `/dev/net/tun`. O estado fica no volume, e o container mantém a mesma máquina na tailnet depois de reiniciar.

1. Gere uma auth key **reutilizável e não efêmera** em https://login.tailscale.com/admin/settings/keys e coloque em `TS_AUTHKEY`.
2. Suba o container: nos logs aparece `[tailscale] conectado: 100.x.y.z (hermes)`.
3. No Hermes Desktop, em **Settings → Gateways → Remote gateway**, use a URL `http://hermes:9119`, entre com o usuário e a senha do painel e salve.

O painel web também fica acessível pela tailnet em `http://hermes:9119`. Com `TS_SERVE=true` (e HTTPS habilitado na tailnet), há também `https://hermes.<tailnet>.ts.net`. Se a chave falhar, o erro vai para o log e o painel sobe do mesmo jeito.

## Só o Dockerfile

A imagem não depende do compose: tudo que ela precisa está no Dockerfile.

```bash
docker build -t hermes-ubuntu .
docker run -d --name hermes -p 127.0.0.1:9119:9119 -v hermes-data:/root/.hermes \
  -e OPENROUTER_API_KEY=... -e TS_AUTHKEY=tskey-auth-... hermes-ubuntu
docker exec hermes cat /root/.hermes/dashboard-password
```

## Uso

```bash
cp .env.example .env      # preencha a chave do provedor de modelo (ex.: OPENROUTER_API_KEY)
make build
make up                   # painel web em http://localhost:9119
make password             # senha gerada do painel (usuário: admin)
make hermes               # Hermes CLI interativo, cwd /workspace
make test                 # smoke test de todas as capacidades
```

| Alvo | O que faz |
|------|-----------|
| `make shell` | bash como root dentro do container |
| `make setup` | `hermes setup` (provedor, chaves) |
| `make logs` | logs do painel |
| `make down` | para o container e mantém o estado |
| `make clean` | para o container e **apaga o volume de estado** |

## Onde ficam os dados

- `./workspace` → `/workspace`: scripts e arquivos do agente, visíveis no host.
- Volume `hermes-data` → `/root/.hermes`: config, sessões, memórias, skills e a senha do painel.

## Isolamento

O agente é root **apenas dentro do container**. O compose não usa `privileged` nem monta `/var/run/docker.sock`, e o painel fica publicado só em `127.0.0.1` no host. Para expor o painel na rede, troque o mapeamento em `docker-compose.yml` para `"9119:9119"` e defina uma senha forte em `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`.
