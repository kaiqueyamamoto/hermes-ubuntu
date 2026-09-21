# ubuntu-hermes

Container Ubuntu 24.04 com o [Hermes Agent](https://hermes-agent.nousresearch.com) rodando como **root**, e o painel web ligado desde o boot.

Dentro do container o agente pode:

- atualizar e instalar pacotes (`apt-get update` / `apt-get install`)
- criar e executar scripts Python (`python3`, `pip`, `venv`)
- acessar a internet normalmente
- controlar um navegador: Google Chrome no amd64, Chromium do Playwright no arm64 (Apple Silicon). O Google Chrome não tem build para Linux arm64.

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
