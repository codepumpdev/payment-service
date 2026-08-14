# ADR-004 — Padrão de Resposta das APIs

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 3, origem: ADR-009 de `auth-service`) fixa o formato de resposta por tipo de operação (`GET` único, `GET` lista, `POST` criação, `PUT`/`PATCH`, `DELETE`) e o envelope de erro aninhado (seção 4, origem: `auth-service`). Nenhum desvio foi identificado para `Payment Service` — mesma adoção direta já feita por `billing-service` (ADR-004 daquele serviço).

> **Atualização (2026-08-14):** a seção 4 passou a definir o `ErrorResponse` plano da codepump-lib (seção 18) — ver contratos/17-api-contracts.md.

## Decisão

`Payment Service` adota integralmente o padrão organizacional:

* `GET /v1/payments/{id}` → corpo com os dados do recurso.
* `GET /v1/payments?billingId=...` → `{ "content": [...], "page", "size", "totalElements", "totalPages" }`.
* `POST /v1/payments` → `201 Created`, header `Location`, corpo com o recurso criado (exceto reenvio de `idempotencyKey`, que responde `200 OK`).
* `POST /v1/payments/{id}/cancel`\* → `200 OK` + recurso atualizado.
* `POST /v1/payments/webhooks/{provider}` → `200 OK`, sem corpo relevante (ação, não recurso).
* Envelope de erro: ~~`{ "error": { "code": "CODIGO_DO_ERRO", "message": "Descrição legível" } }` — sem desvio.~~ **Atualização (2026-08-14):** envelope de erro alinhado ao `ErrorResponse` canônico da `codepump-lib` (`padrao-desenvolvimento.md` seção 4 e 18) — formato plano `{ "timestamp", "status", "code", "message", "path"?, "correlationId"?, "errors"?[] }`; identificação pelo `code`, nunca pela `message`. Ver exemplo em `contratos/17-api-contracts.md` (Convenções).

## Consequências

### Positivas

- Consistência de contrato entre todos os serviços — nenhuma curva de aprendizado adicional para consumidores já integrados com `billing-service`/`person-service`.

### Negativas

- Nenhuma identificada.

## Critérios para reavaliar

Nenhum.

## Nota de integração

* `contratos/17-api-contracts.md`.
* `codepump/codepump/docs/padrao-desenvolvimento.md`, seções 3-4.
