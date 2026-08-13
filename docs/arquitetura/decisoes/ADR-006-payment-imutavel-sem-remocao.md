# ADR-006 — Payment é Registro Imutável: Nenhuma Remoção Física nem Lógica

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 5) fixa `DELETE` físico vs. `PUT`/`PATCH` lógico (`inactivatedAt`) como o padrão organizacional default de remoção. Nenhum dos dois se aplica diretamente a um `Payment`: o documento funcional nunca descreve remover um pagamento — descreve, em vez disso, que uma tentativa recusada nunca é alterada, e que uma nova tentativa é sempre um novo `Payment` (seção 23) — situação análoga à de `billing-service`, que desviou do padrão de remoção física/lógica ao modelar cancelamento como transição de estado (ADR-006 daquele serviço), mas aqui a razão é ainda mais direta: um `Payment` é, por natureza, um registro histórico de uma tentativa de movimentação financeira — alterá-lo ou removê-lo destruiria a própria evidência da tentativa.

## Decisão

`Payment Service` nunca implementa `DELETE` físico de um Payment, nem remoção lógica (`inactivatedAt`) — nenhum dos dois padrões se aplica. Em vez disso: (a) o `status` de um Payment evolui através da máquina de estados fechada (BD-07), nunca por edição livre de campo; (b) um Payment em estado terminal desfavorável (`REJECTED`, `CANCELLED`) nunca é reaproveitado — uma nova tentativa é sempre um novo registro (BD-12); (c) o único "cancelamento" existente (`PENDING → CANCELLED`, endpoint assumido `POST /v1/payments/{id}/cancel`\*) é uma transição de estado, não uma remoção — o registro permanece integralmente, com todo o histórico.

## Consequências

### Positivas

- Nenhum dado financeiro histórico é perdido, mesmo em caso de erro operacional ou tentativa recusada — auditoria e reconciliação futura ficam sempre possíveis.
- Elimina qualquer ambiguidade sobre "o que significa excluir um pagamento" — pergunta que nunca precisa ser respondida, porque a operação não existe.

### Negativas

- A tabela `payments` cresce indefinidamente, sem nenhum mecanismo de expurgo nesta versão — aceito, mesmo critério de simplicidade inicial já usado por outros serviços (retenção/expurgo só quando houver necessidade real).

## Critérios para reavaliar

Se uma exigência legal ou de negócio exigir expurgo de dado financeiro após um período de retenção — definir política própria quando isso ocorrer (mesmo critério já usado por `notification-service`, ADR-013 daquele serviço, para retenção de histórico de entrega).

## Nota de integração

* `dominio/03-business-decisions.md` (BD-07, BD-12).
* `dominio/08-aggregates.md` (invariante 10).
* `contratos/17-api-contracts.md`.
* `codepump/codepump/docs/padrao-desenvolvimento.md`, seção 5.
