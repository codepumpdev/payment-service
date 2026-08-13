# ADR-016 — Estorno: Modelado Desde a v1, Somente Reativo, Sem Endpoint de Iniciar Estorno

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

Ver `dominio/03-business-decisions.md`, BD-08, para o levantamento completo da tensão textual entre as seções 9, 24, 25, 35 e 36 do documento funcional. Em resumo: os status `REFUNDED`/`PARTIALLY_REFUNDED` e o evento `PAYMENT_REFUNDED` fazem parte do catálogo "a utilizar inicialmente" (seções 9, 25), mas a lista exclusiva de "Primeira Versão" (seção 35) não inclui nenhum endpoint de estorno, e a seção 24 abre com "Implemente posteriormente o estorno".

## Decisão

Esta é uma decisão **arquitetural** (como o sistema é desenhado para lidar com essa tensão), complementar à decisão de negócio já registrada em BD-08: o Serviço de Transição de Status (ADR-013) aceita transições para `REFUNDED`/`PARTIALLY_REFUNDED` vindas exclusivamente do fluxo de webhook (ES-06) — nunca de uma chamada HTTP de um Sistema Consumidor. `POST /v1/payments/{id}/refund` é documentado em `17-api-contracts.md` (payload, contrato) para referência futura, mas retorna `501 NAO_IMPLEMENTADO`\* (assumido) ou não é registrado na tabela de rotas ativas nesta versão — decisão de implementação específica, a confirmar na etapa de código.

## Consequências

### Positivas

- Contrato futuro já documentado (`17-api-contracts.md`), reduzindo retrabalho de design quando o endpoint for de fato implementado.
- Nenhuma capacidade de iniciar movimentação de estorno é exposta antes de uma decisão de negócio explícita sobre quem pode autorizá-la (Perfil `PAYMENT_REFUND` já reservado, mas sem uso nesta versão).

### Negativas

- Um usuário/operador não tem, nesta versão, nenhuma forma de solicitar um estorno através do `Payment Service` — só reagir a um estorno já feito por outro canal (banco, painel do provedor).

## Critérios para reavaliar

Confirmação do usuário sobre a leitura de BD-08 (Hotspot H03); implementação de `POST /v1/payments/{id}/refund` quando houver necessidade real de negócio.

## Nota de integração

* `dominio/03-business-decisions.md` (BD-08).
* `dominio/09-domain-state-machines.md`.
* `contratos/17-api-contracts.md`.
* `dominio/01-event-storming-big-picture.md` (Hotspot H03).
