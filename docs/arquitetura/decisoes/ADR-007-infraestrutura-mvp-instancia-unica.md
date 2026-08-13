# ADR-007 — Infraestrutura do MVP: PostgreSQL em Instância Única, Sem Backup/Replicação Inicial

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 8, origem: ADR-016 de `auth-service`) fixa PostgreSQL em instância única, sem cluster/réplica/backup automatizado, como ponto de partida padrão para todo novo serviço em estágio inicial — dimensionar backup sem dado real de volume é arbitrário.

## Decisão

`Payment Service` adota diretamente o padrão organizacional: PostgreSQL em instância única no MVP, sem backup/restauração automatizados, sem réplica de leitura, sem failover automático — mesma decisão de `billing-service` (ADR-007 daquele serviço), sem nenhum desvio.

## Consequências

### Positivas

- Infraestrutura mínima adequada ao porte da empresa e ao estágio do serviço.

### Negativas

- Ponto único de falha (SPOF) aceito deliberadamente — perda de dado financeiro em caso de falha catastrófica de disco, sem backup, é um risco conhecido e aceito nesta fase (tensão registrada, RNF-08).

## Critérios para reavaliar

Definir backup/replicação assim que houver dado real de volume/criticidade — mesmo critério de todos os serviços já documentados.

## Nota de integração

* `arquitetura/15-infrastructure.md`.
* `requisitos/11-non-functional-requirements.md` (RNF-08).
* `codepump/codepump/docs/padrao-desenvolvimento.md`, seção 8.
