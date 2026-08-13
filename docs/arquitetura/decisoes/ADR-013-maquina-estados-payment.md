# ADR-013 — Máquina de Estados de Payment e Regras de Transição

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

O documento funcional (seções 9-10) define um catálogo fechado de sete status e uma tabela de transições permitidas/proibidas explícita — sem a mesma imprecisão encontrada em `billing-service` (que precisou reconciliar um diagrama simplificado com uma enumeração textual mais completa); aqui o diagrama e a lista de proibições são diretamente consistentes.

## Decisão

`Payment Service` implementa a máquina de estados fechada descrita em `dominio/09-domain-state-machines.md` através de um Serviço de Domínio dedicado (Serviço de Transição de Status, `07-domain-services.md`), único ponto do sistema autorizado a alterar `payments.status`. Toda transição é validada contra a tabela fechada antes de ser aplicada; toda transição aplicada grava histórico na mesma transação (RNF-04). `REJECTED`, `CANCELLED` e `REFUNDED` são estados terminais — nenhuma exceção, nem administrativa; `PARTIALLY_REFUNDED` é tratado como terminal nesta versão por ausência de transição definida a partir dele.

## Consequências

### Positivas

- Elimina uma classe inteira de inconsistência de status por `UPDATE` direto — centraliza a única fonte de verdade sobre "o que pode virar o quê".
- Testável isoladamente, sem depender de HTTP/banco/provedor (mesmo princípio de Clean Architecture, ADR-003).

### Negativas

- Nenhuma identificada — é estritamente mais seguro que a alternativa (permitir `UPDATE` de status livre).

## Critérios para reavaliar

Quando o Hotspot H01 (provedor real) for resolvido — pode revelar estados intermediários específicos do provedor; quando o Hotspot H03 (estorno) for resolvido — pode exigir definir acumulação de `PARTIALLY_REFUNDED`.

## Nota de integração

* `dominio/03-business-decisions.md` (BD-07, BD-08).
* `dominio/09-domain-state-machines.md`.
* `dominio/07-domain-services.md`.
* `modelo-dados/19-data-model.md` (`payments.status CHECK`).
