# ADR-009 — Padrão de Armazenamento de Logs

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 7.2, origem: ADR-020 de `auth-service`/ADR-012 de `notification-service`) fixa o padrão de armazenamento de log em arquivo, volume compartilhado, fora do container.

## Decisão

`Payment Service` adota diretamente o padrão organizacional: diretório `/apps/logs/prod/payment-service/`; arquivos `payment-service-[date]-[pod-id]-[sequence].log`/`.err`; JSON estruturado (`log/slog`); limites de 10 MB por arquivo, 10 arquivos, 100 MB por aplicação, com remoção automática do mais antigo. Campos mínimos: `timestamp`, `level`, `message`, mais `paymentId`, `billingId`, `provider`, `providerPaymentId`, `status`, `operation`, `correlationId` quando disponíveis (BD-19). Nunca grava dado sensível (BD-15).

## Consequências

### Positivas

- Consistência operacional com todos os serviços já documentados; equipe de suporte já sabe onde procurar.

### Negativas

- Nenhuma identificada.

## Critérios para reavaliar

Adotar plataforma especializada de observabilidade (Elasticsearch, Loki, etc.) somente quando o volume de aplicações ou necessidade operacional justificar — mesmo critério de `padrao-desenvolvimento.md`, seção 7.2.

## Nota de integração

* `arquitetura/15-infrastructure.md`.
* `dominio/03-business-decisions.md` (BD-15, BD-19).
* `requisitos/11-non-functional-requirements.md` (RNF-11).
* `codepump/codepump/docs/padrao-desenvolvimento.md`, seção 7.2.
