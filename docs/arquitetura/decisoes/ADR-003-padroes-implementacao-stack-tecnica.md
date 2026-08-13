# ADR-003 — Padrões de Implementação e Stack Técnica (Go)

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 2, origem: ADR-015 de `auth-service`) fixa a stack técnica concreta (framework HTTP, acesso a banco, migração de schema, formatação, lint) e a estrutura de pacotes (Clean Architecture simplificada) para todo novo serviço em Go.

## Decisão

`Payment Service` adota integralmente:

```text
Framework HTTP ....... net/http (stdlib) + chi
Acesso a PostgreSQL ... pgx / pgxpool — sem ORM, SQL explícito
Migração de schema .... golang-migrate
Formatação ............ gofmt
Análise estática ...... go vet
Lint .................. golangci-lint
```

Estrutura de pacotes:

```text
cmd/payment-service/main.go
internal/
  domain/          # Payment, máquina de estados, invariantes — nunca importa chi/pgx/detalhe de provedor
  application/      # casos de uso (Criar Payment, Processar Webhook, ...)
  infrastructure/    # PostgreSQL, JWT, OpenBao, PaymentProvider concreto
  interfaces/        # HTTP handlers, DTOs
  config/
migrations/
```

A camada de provedor (`PaymentProvider`, BD-13) vive em `internal/infrastructure/provider/` — nunca em `internal/domain/`.

## Consequências

### Positivas

- Domínio protegido de detalhe de infraestrutura — trocar de provedor, ou de driver de banco, não exige alterar `internal/domain/`.
- Consistência com todos os serviços já documentados.

### Negativas

- Nenhuma identificada.

## Critérios para reavaliar

Nenhum — mesma decisão de todos os serviços já documentados.

## Nota de integração

* `arquitetura/13-architecture.md`.
* `codepump/codepump/docs/padrao-desenvolvimento.md`, seção 2.
