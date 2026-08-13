# ADR-017 — Ambiente Local via Docker Compose

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

O documento funcional (seção 35) inclui "Docker Compose" na lista exclusiva de "Primeira Versão" — mesmo requisito já implementado por `billing-service`/`person-service`/`storage-service`/`notification-service`/`auth-service`, para viabilizar desenvolvimento e teste local sem depender de infraestrutura compartilhada.

## Decisão

`Payment Service` fornece um `docker-compose.yml` na raiz do repositório, subindo: a aplicação (`payment-service`), PostgreSQL (mesma versão major usada em produção), e um stub/mock local do `Payment Provider` (necessário para testar o fluxo de criação → envio → webhook sem depender do provedor real em ambiente local, dado que o provedor real ainda não está definido, Hotspot H01). `Billing Service`/`Person Service`/`Notification Service`/`auth-service` não são subidos por este compose — assumidos como já rodando localmente ou mockados via variável de configuração apontando para ambiente de desenvolvimento compartilhado (mesma convenção já usada pelos demais serviços).

## Consequências

### Positivas

- Onboarding rápido de um novo desenvolvedor — `docker-compose up` sobe o essencial para começar a trabalhar.
- Stub do provedor permite testar o fluxo de webhook localmente, sem esperar a integração real com H01 resolvido.

### Negativas

- Stub do provedor precisa ser mantido em paralelo à implementação real — overhead pequeno, aceito pelo ganho de produtividade em desenvolvimento local.

## Critérios para reavaliar

Nenhum — mesmo padrão já validado pelos demais serviços.

## Nota de integração

* `produto/visao-do-produto.md`, seção 10.
* `dominio/01-event-storming-big-picture.md` (Hotspot H01).
