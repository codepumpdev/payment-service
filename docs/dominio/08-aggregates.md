# Agregados — Payment Service

> Consolida, a partir de `05-bounded-contexts.md`, `09-domain-state-machines.md` e `19-data-model.md`, o **agregado real** deste serviço: raiz, invariantes e fronteira de consistência transacional. Mesmo formato de `billing-service`/`person-service`/`storage-service`.

---

## Convenção

O agregado é descrito por: **Raiz**, **Contém** (entidades/VOs internos que só existem através da raiz), **Invariantes** (regras que devem valer sempre, ao final de qualquer transação) e **Fronteira transacional**.

Princípio geral: nenhuma transação cruza este agregado com um sistema externo (`Billing Service`, `Person Service`, `Payment Provider`, `Notification Service`) — mudanças coordenadas com esses sistemas são sempre transações locais seguidas de chamadas HTTP síncronas fora da transação de banco (BD-14, BD-17).

---

## BC-01 — Payment

### Agregado: Payment

**Raiz:** Payment

**Contém:** Histórico de Status (0..N) — só existe através do Payment (`payment_id` obrigatório, sem sentido de negócio isolado); Evento de Provedor (0..N) — associado a um Payment quando localizado por `providerPaymentId`, existe mesmo antes de um Payment ser localizado (registro do webhook recebido é preservado independentemente).

**Invariantes:**

1. `status` só transiciona conforme a máquina fechada de `09-domain-state-machines.md` (BD-07) — nenhuma operação de domínio aplica um `status` fora do catálogo, nem uma transição não listada.
2. `APPROVED`, `REJECTED` e `CANCELLED` nunca retornam a `PENDING`/`PROCESSING`; `REFUNDED` nunca retorna a `APPROVED`; `CANCELLED` nunca avança a `APPROVED` — transições explicitamente proibidas (BD-07).
3. `type` é imutável após a criação (BD-02) — nenhuma operação de domínio altera o `type` de um Payment já existente.
4. `amount`/`currency` são imutáveis após a criação — nenhuma operação de domínio altera o valor original de um Payment (diferente de `billing-service`, aqui não existe conceito de "valor pago parcialmente restante" dentro do próprio Payment; um pagamento parcial de uma cobrança é modelado como múltiplos Payments, BD-12).
5. `providerPaymentId` é preenchido no máximo uma vez, no momento em que o provedor aceita a operação (transição `PENDING → PROCESSING`) — nunca reatribuído depois.
6. Toda transição de `status` grava uma linha em Histórico de Status na mesma transação — nenhum Payment tem uma sequência de `status` ao longo do tempo sem o Histórico correspondente.
7. `idempotencyKey` é único no contexto da `application` que criou o Payment (BD-09) — nunca dois Payments com a mesma combinação.
8. `(provider, providerEventId)` é único em Evento de Provedor (BD-10) — nunca dois registros para o mesmo evento de webhook.
9. Nenhum dado financeiro de destino (chave Pix, conta bancária, agência, número de conta, dado de cartão, CVV) é armazenado por este agregado, em nenhuma tabela (BD-15, BD-16) — a resolução desse dado é sempre feita pelo `Person Service`, fora da fronteira deste agregado.
10. Um Payment `REJECTED`/`CANCELLED` nunca é reaproveitado para uma nova tentativa — uma nova tentativa é sempre um novo Payment (BD-12).

**Fronteira transacional:** criar um Payment (ES-01) grava o Payment e a primeira linha de Histórico de Status em uma única transação. Aplicar o resultado de um webhook (ES-06) grava o registro em Evento de Provedor, atualiza o Payment e grava uma nova linha de Histórico de Status, também em uma única transação — nunca o Payment é atualizado sem o Histórico correspondente. A comunicação com `Billing Service`/`Person Service`/`Payment Provider`/`Notification Service` acontece **fora** dessas transações (antes, para obter dado necessário; depois, para notificar o resultado) — nenhuma chamada HTTP externa ocorre dentro de uma transação de banco aberta.

---

## Cascatas entre agregados

Nenhuma cascata automática existe neste serviço — um único agregado (Payment) cobre todo o domínio de BC-01; BC-02 (Auditoria) não é um agregado, é um BC de leitura/registro que reage aos eventos publicados por BC-01 (`06-context-map.md`), sempre fora da transação principal (registro de auditoria não bloqueia nem reverte a operação de negócio que o originou, mesmo padrão de `billing-service`/`person-service`/`storage-service`).
