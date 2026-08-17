# Contratos de Eventos — Payment Service

> Este serviço usa RabbitMQ **exclusivamente para auditoria**: o módulo de Auditoria (BC-02) projeta cada operação financeira relevante para um `AuditEvent` canônico da `codepump-lib` e o publica no exchange `audit.events` (`padrao-desenvolvimento.md` seção 17 e seção 17.3/18) — mesmo padrão de `organization-service` (ADR-011) e `alert-service` (ADR-010), como publicador, nunca consumidor. Publicação best-effort, nunca bloqueia a operação de negócio. A comunicação de negócio (`Billing Service`/`Person Service`/`Notification Service`/`Payment Provider`) permanece em HTTP síncrono (ADR-010), sem fila. Os "eventos" abaixo são: (a) eventos de domínio internos, despachados em memória, consumidos pelo módulo de Auditoria (BC-02) — que os projeta para `AuditEvent` e os publica em `audit.events`; e (b) chamadas HTTP síncronas de entrada/saída com sistemas externos, nomeadas com o mesmo vocabulário de evento por clareza de domínio, mas sem nenhum mecanismo de fila por trás. Ver a seção "Auditoria — Publicação em `audit.events` (RabbitMQ)", abaixo.

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

## Auditoria — Publicação em `audit.events` (RabbitMQ)

O módulo de Auditoria (BC-02), ao consumir cada evento de domínio interno acima, projeta a operação financeira relevante em um `AuditEvent` canônico da `codepump-lib` (`padrao-desenvolvimento.md`, seções 17.3 e 18) e o **publica no exchange `audit.events`** — este serviço é **publicador, nunca consumidor** desse exchange (o consumo é responsabilidade exclusiva de `audit-service`). RabbitMQ é usado **exclusivamente para auditoria**; nenhuma fila própria de negócio, nenhum outro exchange.

**Convenções** (mesmas de `organization-service`/`alert-service`):

* **Exchange:** `audit.events` — `topic`, `durable`; mensagens `delivery_mode: 2` (persistente).
* **Routing key:** `audit.event.published`.
* **Publisher Confirms** habilitado — publicação não confirmada é tratada como falha, nunca sucesso silencioso.
* **Cliente Go:** `rabbitmq/amqp091-go`.
* **Credencial de conexão** gerida via OpenBao (ADR-008) — ver `arquitetura/15-infrastructure.md`.
* **Fila / DLX / DLQ** de `audit.events` são declaradas e mantidas por `audit-service` — este serviço não as conhece.
* **`correlationId`** = o mesmo `X-Correlation-ID` propagado entre serviços (BD-19).
* **Só ação de negócio, nunca leitura**: nenhuma consulta (`GET`) gera evento de auditoria.
* **Dado mínimo** (BD-15/BD-18): nunca chave Pix, conta bancária, CVV ou dado sensível — só referências (`paymentId`, `billingId`, e, quando útil, `method`/`provider`/`status`/`amount` em `data`).

**Mapeamento do catálogo fechado de auditoria (BD-18) para o `AuditEvent` canônico** — `application: payment-service`, `resource: PAYMENT`, `resourceId: paymentId`, `success` conforme o resultado (operações que falham também são auditadas, `success: false`):

| Operação de auditoria (BD-18) | `action` | `data` (referências mínimas) |
|---|---|---|
| `PAYMENT_CREATED` | `CREATE` | `billingId`, `type` (`RECEIVE`/`PAY`), `method`, `amount` |
| `PAYMENT_APPROVED` | `APPROVE` | `billingId`, `amount`, `provider` |
| `PAYMENT_REJECTED` | `REJECT` | `billingId`, `provider` |
| `PAYMENT_CANCELLED` | `CANCEL` | `billingId` |
| `PAYMENT_REFUNDED` | `REFUND` | `billingId`, `amount` |
| `PAYMENT_PARTIALLY_REFUNDED` | `REFUND` | `billingId`, `amount`, `remainingApproved`, `partial: true` |

`action: PAYMENT`/`REFUND` são ações canônicas de auditoria explicitamente previstas para movimentação de dinheiro (`padrao-desenvolvimento.md`, seção 17.1); aqui usa-se o par `action`/`resource` acima, que mantém o mesmo vocabulário fechado já auditado por este serviço (BD-18) e distingue as transições financeiras entre si.

**Garantias:** Publisher Confirms + publicação **best-effort, nunca bloqueia a operação de negócio** — o Command já está comitado (ou o webhook já processado) antes da tentativa de publicação; uma falha momentânea de RabbitMQ nunca bloqueia a resposta ao Sistema Consumidor nem o `ACK` ao provedor (mesmo tratamento de `organization-service` ADR-011 e `alert-service` ADR-010). A garantia de "nunca perder um evento" depende de ambas as pontas (este serviço + `audit-service`).

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

\*\* **Verificação (Hotspot H03):** o contrato de `billing-service` (`contratos/17-api-contracts.md`, seção 6) documenta `event ∈ {PAYMENT_APPROVED, PAYMENT_REJECTED, PAYMENT_REFUNDED}` — **não inclui `PAYMENT_PARTIALLY_REFUNDED`**. Este serviço pode, na prática, tentar enviar um valor que `billing-service` ainda não aceita. Isso é uma extensão do Hotspot H03 (não um novo Hotspot): a resolução de H03 (se estorno parcial reativo está mesmo em escopo) determina se `billing-service` precisa, primeiro, ampliar aquele `CHECK`/catálogo para aceitar esse evento.
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
* **Conformidade com Tarefas Agendadas (ADR-019):** o padrão organizacional de Tarefas Agendadas via `scheduler-service` (`padrao-desenvolvimento.md`, seção 13) aplica-se a toda a organização. Como este serviço nunca teve nenhum job periódico interno, já está em conformidade com esse padrão sem exigir nenhuma migração — nenhuma goroutine/cron a remover, nenhum endpoint `/internal/*` a expor para o `scheduler-service`.

---

## Evolução

Promover os eventos de domínio internos a mensagens de um broker (RabbitMQ) quando a necessidade de desacoplamento for real (ADR-010) — nenhum consumidor externo real justifica isso hoje. Confirmar `PAYMENT_PARTIALLY_REFUNDED` como evento formal (ou removê-lo do catálogo) quando o Hotspot H03 for resolvido.
