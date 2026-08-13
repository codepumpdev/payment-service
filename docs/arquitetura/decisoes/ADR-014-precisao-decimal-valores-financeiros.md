# ADR-014 — Precisão Decimal para Valores Financeiros

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

O documento funcional (seção 29) é explícito: "não utilize `float` para cálculos financeiros. Utilize representação decimal adequada." Mesma exigência já registrada e implementada por `billing-service` (ADR-013 daquele serviço) — aqui reforçada, já que `Payment Service` lida diretamente com o valor movimentado, não só com um valor de referência.

## Decisão

Todo valor financeiro (`amount`) usa `NUMERIC` no PostgreSQL, tipo decimal na aplicação Go (nunca `float32`/`float64`), e serialização sem perda de precisão em toda API (JSON como número/string sem arredondamento implícito, decisão de serialização específica na implementação). `currency` é um campo explícito, restrito a `BRL` nesta versão (BD-05).

## Consequências

### Positivas

- Elimina uma classe inteira de bug de arredondamento financeiro desde o primeiro dia.

### Negativas

- Nenhuma — é estritamente mais seguro que a alternativa, sem custo de complexidade adicional relevante.

## Critérios para reavaliar

Suportar múltiplas moedas quando houver necessidade real de negócio (seção 36 do documento funcional).

## Nota de integração

* `dominio/03-business-decisions.md` (BD-05).
* `modelo-dados/19-data-model.md` (`payments.amount NUMERIC(14,2)`).
* `contratos/17-api-contracts.md`.
