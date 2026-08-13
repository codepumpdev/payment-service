# ADR-012 — Idempotência de Webhook (`providerEventId`)

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

O documento funcional (seção 19) alerta explicitamente que o provedor "poderá enviar o mesmo webhook mais de uma vez" — comportamento comum em integrações de pagamento, para garantir entrega (at-least-once). Processar o mesmo evento duas vezes poderia, por exemplo, disparar duas chamadas de "informar Billing Service" para a mesma aprovação, ou (num cenário futuro de estorno automático) aplicar um estorno duplicado.

## Decisão

Todo webhook recebido é identificado por `providerEventId`, único no contexto de `provider` (`UNIQUE (provider, provider_event_id)` em `payment_provider_events`, BD-10). Antes de aplicar qualquer transição, o Payment Service verifica se o par `(provider, providerEventId)` já foi processado — se sim, retorna `200 OK` sem reexecutar; se não, processa e registra.

## Consequências

### Positivas

- Reenvio de webhook pelo provedor nunca aplica a mesma transição duas vezes — proteção crítica para consistência financeira.

### Negativas

- Exige uma tabela dedicada (`payment_provider_events`) só para deduplicação, com todo evento recebido persistido mesmo quando não corresponde a nenhum Payment localizável — aceito, é o mecanismo mais direto e auditável.

## Critérios para reavaliar

Nenhum — mecanismo já suficiente para o volume esperado nesta fase.

## Nota de integração

* `dominio/03-business-decisions.md` (BD-10).
* `dominio/07-domain-services.md` (Serviço de Idempotência).
* `modelo-dados/19-data-model.md` (`payment_provider_events`, `UNIQUE (provider, provider_event_id)`).
* `contratos/17-api-contracts.md`.
