# Contratos de Eventos — Payment Service

> Diferente de `notification-service` (RabbitMQ), este serviço não publica em nenhum broker nesta versão (ADR-010) — os "eventos" abaixo são: (a) eventos de domínio internos, despachados em memória, consumidos só pelo módulo de Auditoria (BC-02); e (b) chamadas HTTP síncronas de entrada/saída com sistemas externos, nomeadas com o mesmo vocabulário de evento por clareza de domínio, mas sem nenhum mecanismo de fila por trás.

---

## Eventos de Domínio Internos (despachante em memória)

| Evento | Payload (conceitual) | Consumidor | Observação |
|---|---|---|---|
| `PAYMENT_CREATED` | `paymentId: uuid, billingId: uuid, type: string, application: string, actor: string` | Auditoria (BC-02) | Disparado ao final de ES-01. |
| `PAYMENT_PROCESSING` | `paymentId: uuid, provider: string, providerPaymentId: string` | Auditoria (BC-02) | Disparado quando o envio síncrono ao provedor é aceito, ainda dentro de ES-01. |
| `PAYMENT_APPROVED` | `paymentId: uuid, billingId: uuid, amount: decimal, currency: string` | Auditoria (BC-02); outbound para `Billing Service`/`Notification Service` | Disparado ao final de ES-06, quando o provedor confirma aprovação. |
| `PAYMENT_REJECTED` | `paymentId: uuid, billingId: uuid, reason: string \| null` | Auditoria (BC-02); outbound para `Billing Service`/`Notification Service` | Disparado ao final de ES-06, quando o provedor confirma rejeição. |
| `PAYMENT_CANCELLED` | `paymentId: uuid, billingId: uuid, reason: string \| null` | Auditoria (BC-02) | Disparado por `POST /v1/payments/{id}/cancel`\* (assumido). |
| `PAYMENT_REFUNDED` | `paymentId: uuid, billingId: uuid, amount: decimal` | Auditoria (BC-02); outbound para `Billing Service`/`Notification Service` | Disparado ao final de ES-06, só de forma reativa (webhook do provedor, BD-08, Hotspot H03). |
| `PAYMENT_PARTIALLY_REFUNDED`\* | `paymentId: uuid, billingId: uuid, amount: decimal, remainingApproved: decimal` | Auditoria (BC-02); outbound para `Billing Service`/`Notification Service` | Assumido por simetria com o catálogo de status (seção 9 do documento funcional inclui `PARTIALLY_REFUNDED`, mas a seção 25, catálogo de eventos, não cita esse evento explicitamente) — ver Hotspot H03. |

Nunca inclui dado sensível além do mínimo listado (BD-15, BD-18).

---

## Eventos Externos Consumidos (HTTP síncrono inbound)

| Evento | Origem | Mecanismo | Observação |
|---|---|---|---|
| Webhook de confirmação | `Payment Provider` | `POST /v1/payments/webhooks/{provider}`, payload assumido\* (Hotspot H01/H02) | Aplica `PROCESSING → APPROVED`/`REJECTED`, ou `APPROVED → REFUNDED`/`PARTIALLY_REFUNDED` (ES-06). |

---

## Eventos Externos Publicados (HTTP síncrono outbound)

| Evento | Destino | Mecanismo | Observação |
|---|---|---|---|
| `PAYMENT_APPROVED`, `PAYMENT_REJECTED`, `PAYMENT_REFUNDED`, `PAYMENT_PARTIALLY_REFUNDED`\*\* | `Billing Service` | `POST /v1/billings/{id}/payment-events`\* (assumido, contrato já publicado por `billing-service`) | Informa o resultado da movimentação, para os dois sentidos (`RECEIVE`/`PAY`) igualmente — BD-01, ES-07. |

\*\* **Nota de 2026-08-13 (verificação):** o contrato de `billing-service` (`contratos/17-api-contracts.md`, seção 6) documenta hoje `event ∈ {PAYMENT_APPROVED, PAYMENT_REJECTED, PAYMENT_REFUNDED}` — **não inclui `PAYMENT_PARTIALLY_REFUNDED`**. Este serviço pode, na prática, tentar enviar um valor que `billing-service` ainda não aceita. Isso é uma extensão do Hotspot H03 (não um novo Hotspot): a resolução de H03 (se estorno parcial reativo está mesmo em escopo) determina se `billing-service` precisa, primeiro, ampliar aquele `CHECK`/catálogo para aceitar esse evento.
| `PAYMENT_APPROVED`, `PAYMENT_REJECTED`, `PAYMENT_REFUNDED` | `Notification Service` | Chamada HTTP síncrona, API já documentada daquele serviço | BD-14, seção 27 do documento funcional — `Notification Service` decide os canais; `PAYMENT_PARTIALLY_REFUNDED` não está na lista explícita da seção 27, tratado como não notificado diretamente nesta versão (assumido\*). |

---

## Comunicação Outbound Adicional (fora do despachante em memória)

| Destino | Gatilho | Mecanismo | Observação |
|---|---|---|---|
| `Billing Service` (consulta) | Criação de Payment (RF-01) | `GET /v1/billings/{id}`\* | Consulta de valor disponível antes de criar — BD-11, não é em si um "evento", mas uma dependência síncrona crítica do fluxo de criação. |
| `Person Service` (consulta) | Criação de Payment `PAY` (RF-04) | `GET /v1/persons/{personId}/receiving-accounts`\* | BD-16. |
| `Payment Provider` (envio) | Criação de Payment (RF-01) | Contrato específico do provedor (Hotspot H01) | Envio síncrono da operação, dentro da mesma chamada de criação. |

---

## Jobs Internos — Não São Eventos de Domínio

* Nenhum job interno periódico existe neste serviço nesta versão — diferente de `billing-service` (verificação de vencimento). Toda transição é reativa (criação ou webhook).

---

## Evolução

Promover os eventos de domínio internos a mensagens de um broker (RabbitMQ) quando a necessidade de desacoplamento for real (ADR-010) — nenhum consumidor externo real justifica isso hoje. Confirmar `PAYMENT_PARTIALLY_REFUNDED` como evento formal (ou removê-lo do catálogo) quando o Hotspot H03 for resolvido.
