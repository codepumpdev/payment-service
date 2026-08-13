# ADR-005 — Versionamento de API via Prefixo de URL

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 3, origem: ADR-007 de `auth-service`) fixa prefixo `/v1` em toda rota de domínio, com exceções de convenção de mercado (`/health`) ou de contrato de terceiro (webhook, ver Decisão abaixo).

## Decisão

Todo endpoint de domínio deste serviço usa prefixo `/v1` (`POST /v1/payments`, `GET /v1/payments/{id}`, etc.). Duas exceções deliberadas:

* `GET /health` — convenção de mercado, mesma exceção de todos os serviços.
* `POST /v1/payments/webhooks/{provider}` — **mantém** o prefixo `/v1` (diferente de `POST /oauth2/v1/token/service` de `auth-service`, que é uma exceção deliberada ao padrão): o webhook é um recurso próprio deste serviço, não uma convenção de mercado externa: nenhuma razão para fugir do prefixo.

Mudança incompatível (remover rota/campo, mudar tipo, remover código de erro publicado) exige `/v2`; mudança aditiva não.

## Consequências

### Positivas

- Consistência com todos os serviços já documentados; nenhuma ambiguidade sobre quando abrir uma nova versão principal.

### Negativas

- Nenhuma identificada.

## Critérios para reavaliar

Nenhum.

## Nota de integração

* `contratos/17-api-contracts.md`.
* `codepump/codepump/docs/padrao-desenvolvimento.md`, seção 3.
