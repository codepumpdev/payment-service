# Planejamento — Histórias

> Uma História por Requisito Funcional (`../requisitos/10-functional-requirements.md`), agrupadas nos Épicos de `20-epics.md` — **exceto RF-04**, que não tem História própria: por ser disparado internamente como parte do fluxo síncrono de RF-01 (nunca invocado isoladamente por um Sistema Consumidor, `20-epics.md`, E1), sua obtenção de dados do recebedor é coberta dentro da História de RF-01, abaixo. 8 Histórias no total. Cada História traz Descrição, Objetivo, Regras de negócio, Critérios de aceite, Dependências e Impactos, mais a divisão Backend/Frontend/Banco/Testes — mesmo formato de `billing-service`/`person-service`/`storage-service`.
>
> **Critérios de aceite** apontam para os cenários Gherkin já escritos em `../requisitos/12-acceptance-criteria.md`, sem duplicar.

---

## Convenção da divisão Backend/Frontend/Banco/Testes

* **Backend:** endpoint HTTP (`../contratos/17-api-contracts.md`), quando existir.
* **Frontend:** o documento funcional fornecido pelo usuário não define nenhum Painel Administrativo para este serviço — "N/A" em toda História desta versão. **Exceção (2026-08-14):** a tela administrativa `GET /admin/config` (Interface Web de Configuração — `arquitetura/decisoes/ADR-020-interface-web-configuracao.md`) é a única superfície de UI desta versão, adotada por padrão organizacional (`padrao-desenvolvimento.md` seção 23), não por requisito funcional próprio — administra a configuração do serviço, transversal às Histórias, não uma delas.
* **Banco:** tabela(s) de `../modelo-dados/19-data-model.md` afetadas.
* **Testes:** Unitário, Integração, Contrato, E2E (`padrao-desenvolvimento.html`, seção 10).

---

## E1 — Payment

### RF-01 — Criação de Payment

**Descrição:** receber, de um Sistema Consumidor autenticado, o pedido de criação de um pagamento (`RECEIVE` ou `PAY`), de forma idempotente, sempre relacionado a uma cobrança existente.
**Objetivo:** porta de entrada síncrona do serviço.
**Regras de negócio:** BD-02, BD-03, BD-05, BD-06, BD-09, BD-11, BD-13.
**Critérios de aceite:** `12-acceptance-criteria.md`, RF-01 (7 cenários).
**Dependências:** nenhuma.
**Impactos:** Payment (BC-01); dispara RF-04 (quando `PAY`) e envio ao provedor.

| Frente | Detalhe |
|---|---|
| Backend | `POST /v1/payments` (`17-api-contracts.md`, seção 1); abstração `PaymentProvider` (`07-domain-services.md`) |
| Frontend | N/A |
| Banco | `payments`, `payment_status_history` (primeira linha) |
| Testes | Unitário (validação de campos, precisão decimal), Integração (índice único de idempotência sob concorrência; mock de `Billing Service`/`Person Service`/provedor), Contrato (`400`/`401`/`403`/`404`/`409`/`422`) |

### RF-02 — Consulta de Payment por Identificador

**Descrição:** permitir recuperar o estado corrente de um pagamento já criado.
**Objetivo:** único ponto de leitura individual.
**Regras de negócio:** BD-03, BD-04.
**Critérios de aceite:** `12-acceptance-criteria.md`, RF-02 (2 cenários).
**Dependências:** RF-01.
**Impactos:** Payment (BC-01).

| Frente | Detalhe |
|---|---|
| Backend | `GET /v1/payments/{id}` (`17-api-contracts.md`, seção 2) |
| Frontend | N/A |
| Banco | `payments` (leitura) |
| Testes | Unitário, Contrato (`404`) |

### RF-03 — Consulta de Payments por Cobrança

**Descrição:** permitir localizar todos os pagamentos relacionados a uma cobrança.
**Objetivo:** visão consolidada de tentativas por cobrança.
**Regras de negócio:** BD-12.
**Critérios de aceite:** `12-acceptance-criteria.md`, RF-03 (2 cenários).
**Dependências:** RF-01.
**Impactos:** Payment (BC-01).

| Frente | Detalhe |
|---|---|
| Backend | `GET /v1/payments?billingId=...` (`17-api-contracts.md`, seção 3) |
| Frontend | N/A |
| Banco | `payments` (índice `billing_id`) |
| Testes | Unitário (combinação de filtros), Integração (paginação, múltiplas tentativas) |

### RF-08 — Registro de Histórico de Status

**Descrição:** garantir rastreabilidade completa de toda mudança de status.
**Objetivo:** histórico append-only, auditável.
**Regras de negócio:** BD-07.
**Critérios de aceite:** `12-acceptance-criteria.md`, RF-08 (1 cenário).
**Dependências:** RF-01, RF-06 (qualquer transição de status).
**Impactos:** Payment (BC-01).

| Frente | Detalhe |
|---|---|
| Backend | Serviço de Transição de Status (`07-domain-services.md`) — sem endpoint HTTP próprio nesta versão, exceto a consulta de leitura (seção 7 de `17-api-contracts.md`) |
| Frontend | N/A |
| Banco | `payment_status_history` |
| Testes | Integração (nenhuma transição sem histórico correspondente, mesma transação) |

---

## E2 — Confirmação do Provedor

### RF-05 — Recebimento de Webhook do Provedor

**Descrição:** receber, de forma idempotente e autenticada, a notificação assíncrona do `Payment Provider`.
**Objetivo:** ponto de entrada inbound do provedor.
**Regras de negócio:** BD-10; Hotspot H01, Hotspot H02.
**Critérios de aceite:** `12-acceptance-criteria.md`, RF-05 (3 cenários).
**Dependências de runtime:** RF-01 (Payment já em `PROCESSING`); depende de uma integração externa ainda não formalizada (`Payment Provider`).
**Impactos:** Payment (BC-01); dispara RF-06.

| Frente | Detalhe |
|---|---|
| Backend | `POST /v1/payments/webhooks/{provider}` (`17-api-contracts.md`, seção 4); Serviço de Integração com Provedor (`07-domain-services.md`) |
| Frontend | N/A |
| Externo | `Payment Provider` (inbound, autenticação própria do provedor) |
| Banco | `payment_provider_events` (escrita) |
| Testes | Unitário (dedupe de evento), Integração (mock do provedor, reenvio de webhook), Contrato (`401`/`400`/`404`) |

**Nota:** esta é a História de maior risco de retrabalho do plano — o contrato de payload/autenticidade (Hotspot H01/H02) deve ser implementado atrás de uma interface isolada (`PaymentProvider`, ADR-015), para que uma mudança futura não vaze para o restante do domínio.

### RF-06 — Atualização de Status por Confirmação do Provedor

**Descrição:** refletir, no Payment, o resultado (aprovação, rejeição, estorno) informado pelo provedor.
**Objetivo:** transição automática para `APPROVED`/`REJECTED`/`REFUNDED`/`PARTIALLY_REFUNDED` a partir de um evento externo.
**Regras de negócio:** BD-07, BD-08; Hotspot H03.
**Critérios de aceite:** `12-acceptance-criteria.md`, RF-06 (4 cenários).
**Dependências de runtime:** RF-05 (webhook já validado e localizado).
**Impactos:** Payment (BC-01); dispara RF-07 e RF-08 e RF-09.

| Frente | Detalhe |
|---|---|
| Backend | Serviço de Transição de Status (`07-domain-services.md`) |
| Frontend | N/A |
| Banco | `payments` (escrita), `payment_status_history` (escrita) |
| Testes | Unitário (transições permitidas/proibidas), Integração (transação atômica payment+histórico) |

---

## E3 — Integração com Billing Service

### RF-07 — Informar Billing Service do Resultado

**Descrição:** propagar ao `Billing Service` o resultado de uma movimentação financeira.
**Objetivo:** manter a obrigação financeira sincronizada com a movimentação real.
**Regras de negócio:** BD-01, BD-14.
**Critérios de aceite:** `12-acceptance-criteria.md`, RF-07 (2 cenários).
**Dependências de runtime:** RF-06 (resultado já aplicado ao Payment).
**Impactos:** nenhum impacto direto no schema deste serviço — chamada outbound.

| Frente | Detalhe |
|---|---|
| Backend | Chamada outbound a `POST /v1/billings/{id}/payment-events`\* (`06-context-map.md`) |
| Frontend | N/A |
| Externo | `Billing Service` (outbound, autenticação M2M) |
| Banco | nenhuma tabela própria — só leitura de `payments` para montar o payload |
| Testes | Unitário (montagem do payload), Integração (mock do `Billing Service`, falha não reverte o Payment) |

---

## E4 — Auditoria

### RF-09 — Auditoria de Operações

**Descrição:** registrar toda operação financeira relevante, sem duplicar dado sensível.
**Objetivo:** rastreabilidade de segurança, distinta do histórico de domínio.
**Regras de negócio:** BD-15, BD-18.
**Critérios de aceite:** `12-acceptance-criteria.md`, RF-09 (1 cenário).
**Dependências:** consome eventos internos de E1/E2 (`06-context-map.md`) — não bloqueia nenhum deles.
**Impactos:** Auditoria (BC-02).

| Frente | Detalhe |
|---|---|
| Backend | Despachante de eventos em memória (`18-event-contracts.md`) — sem endpoint HTTP próprio nesta versão (consulta de auditoria fora do MVP de API, `10-functional-requirements.md`) |
| Frontend | N/A |
| Banco | `audit_logs` |
| Testes | Unitário (mapeamento evento → `operation`), Integração (nenhum dado sensível gravado) |
