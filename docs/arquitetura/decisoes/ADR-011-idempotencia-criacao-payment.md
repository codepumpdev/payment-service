# ADR-011 — Idempotência na Criação de Payment

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

O documento funcional (seção 11) exige `idempotencyKey` obrigatória na criação, com a garantia de que a mesma requisição, reenviada, nunca cria um segundo Payment. Movimentação financeira duplicada por reenvio de requisição (timeout, retry de rede) é um risco direto de dano financeiro real — mais crítico ainda que a idempotência de criação já registrada por `billing-service` (ADR-011 daquele serviço), porque aqui a duplicata dispararia uma segunda cobrança/pagamento real no provedor, não só um registro duplicado.

## Decisão

Toda criação de Payment exige `idempotencyKey`. Verificação de existência é sempre a primeira etapa do fluxo de criação, antes de qualquer outra validação (BD-09) — implementada via `UNIQUE (idempotency_key, application)` no banco, como garantia de última linha contra condição de corrida, complementada por uma consulta prévia para o caminho feliz (retornar o Payment já existente com `200 OK`, não erro).

## Consequências

### Positivas

- Reenvio de requisição nunca duplica uma movimentação financeira real — proteção crítica, não apenas de qualidade de dado.

### Negativas

- Nenhuma identificada.

## Critérios para reavaliar

Nenhum — mesmo padrão já validado por `billing-service`/`notification-service`.

## Nota de integração

* `dominio/03-business-decisions.md` (BD-09).
* `dominio/07-domain-services.md` (Serviço de Idempotência).
* `modelo-dados/19-data-model.md` (`payments`, `UNIQUE (idempotency_key, application)`).
* `contratos/17-api-contracts.md`.
