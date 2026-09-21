COMPOSE := docker compose
EXEC    := $(COMPOSE) exec hermes

.PHONY: build up down logs password hermes shell setup test clean

build:    ## Constrói a imagem
	$(COMPOSE) build

up:       ## Sobe o container com o painel web (http://localhost:9119)
	$(COMPOSE) up -d --wait

down:     ## Para o container (mantém o volume de estado)
	$(COMPOSE) down

logs:     ## Logs do painel/container
	$(COMPOSE) logs -f hermes

password: ## Mostra a senha gerada do painel web
	$(EXEC) cat /root/.hermes/dashboard-password

hermes: up ## Abre o Hermes CLI interativo (root, /workspace)
	$(EXEC) hermes

shell: up ## Bash como root dentro do container
	$(EXEC) bash

setup: up ## Assistente de configuração do Hermes (provedor, chaves)
	$(EXEC) hermes setup

test: up  ## Smoke test das capacidades do container
	$(EXEC) /opt/hermes-tests/smoke.sh

clean:    ## Remove container e volume de estado do Hermes
	$(COMPOSE) down -v
