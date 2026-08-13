# ADR-002 — Linguagem e Runtime de Implementação: Go (Golang)

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 2, origem: ADR-014 de `auth-service`) fixa Go como linguagem/runtime padrão para todo novo serviço, salvo necessidade técnica explícita em contrário. Nenhuma necessidade técnica excepcional foi identificada para `Payment Service`.

## Decisão

`Payment Service` é implementado em Go (Golang), adotando diretamente o padrão organizacional, sem desvio.

## Consequências

### Positivas

- Consistência de stack entre todos os serviços da organização — equipe já capacitada, ferramentas de build/CI já padronizadas.
- Baixo overhead de runtime, adequado a um serviço de alta frequência de chamada síncrona (criação de pagamento, webhook).

### Negativas

- Nenhuma identificada.

## Critérios para reavaliar

Nenhum — mesma decisão de todos os serviços já documentados.

## Nota de integração

* `codepump/codepump/docs/padrao-desenvolvimento.md`, seção 2.
* `produto/visao-do-produto.md`, seção 9.
