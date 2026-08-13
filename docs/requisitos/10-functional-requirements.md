# Requisitos Funcionais — Payment Service

> Mapeamento 1:1 com os fluxos numerados de `../dominio/01-event-storming-big-picture.md`: cada requisito (**RF-XX**) corresponde ao fluxo de mesmo número (**1 a 9**). Critério de aceite mínimo extraído das Regras de cada fluxo, detalhado com a Event Story correspondente (`../dominio/02-event-stories.md`, ES-XX). Mesmo formato de `billing-service`/`person-service`/`storage-service`.
>
> Convenção de origem: cada requisito cita as Decisões de Negócio (BD-XX) que o fundamentam — ver `../dominio/03-business-decisions.md`.

---

## RF-01 — Criação de Payment

**Origem:** Fluxo 1; ES-01.

**Descrição:** Receber, de um Sistema Consumidor autenticado, o pedido de criação de um pagamento (`RECEIVE` ou `PAY`), de forma idempotente, sempre relacionado a uma cobrança existente.

**Critérios de aceite:**

* Dada uma chamada `POST /v1/payments` autenticada por JWT (emitido por `auth-service`, BD-04) com o Perfil `PAYMENT_CREATE`, o payload deve conter `type`, `billingId`, `amount`, `currency`, `method`, `idempotencyKey` — ausência de qualquer um resulta em `400 VALIDACAO_FALHOU`.
* `type` fora de `{RECEIVE, PAY}` → `400 VALIDACAO_FALHOU` (BD-02).
* `currency` diferente de `BRL` → `400 MOEDA_NAO_SUPORTADA` (BD-05).
* `method` não implementado (diferente de `PIX` nesta versão) → `400 METODO_NAO_SUPORTADO` (BD-06).
* Se já existir um Payment com o mesmo `idempotencyKey` na mesma `application`, retorna o Payment já criado (`200 OK`), sem criar duplicata (BD-09).
* `billingId` inexistente (consulta ao `Billing Service`) → `404 COBRANCA_NAO_ENCONTRADA`.
* `amount` ultrapassa o valor disponível da cobrança → `409 VALOR_EXCEDE_COBRANCA` (BD-11).
* Payment criado com `status = PENDING`; se `type = PAY`, RF-04 é disparado antes do envio ao provedor; envio síncrono ao provedor tentado na mesma operação — sucesso transiciona para `PROCESSING`, falha mantém `PENDING`.
* Sucesso retorna `201 Created`, `Location: /v1/payments/{id}`, corpo com o recurso criado (incluindo dado necessário ao pagador concluir a operação, quando aplicável).
* JWT ausente/inválido/expirado → `401 NAO_AUTENTICADO`; Perfil ausente → `403 PERFIL_INSUFICIENTE` — em ambos os casos, nenhum registro é criado.

---

## RF-02 — Consulta de Payment por Identificador

**Origem:** Fluxo 2; ES-02.

**Descrição:** Permitir recuperar o estado corrente de um pagamento já criado.

**Critérios de aceite:**

* `GET /v1/payments/{id}`, Perfil `PAYMENT_READ` — `404 PAYMENT_NAO_ENCONTRADO` se não existir.
* Resposta traz todos os campos de `19-data-model.md`, exceto dados internos de auditoria.

---

## RF-03 — Consulta de Payments por Cobrança

**Origem:** Fluxo 3; ES-03.

**Descrição:** Permitir localizar todos os pagamentos relacionados a uma cobrança — necessário para tentativa recusada, nova tentativa, pagamento parcial, múltiplos pagamentos ou estorno.

**Critérios de aceite:**

* `GET /v1/payments?billingId={billingId}`, Perfil `PAYMENT_READ`; aceita filtros adicionais `status`, `page`, `size`.
* Resposta sempre paginada (`content`, `page`, `size`, `totalElements`, `totalPages`) — nunca lista ilimitada.
* Retorna lista vazia (`200 OK`), nunca `404`, quando nenhum Payment corresponder.

---

## RF-04 — Obtenção de Dados do Recebedor (`PAY`)

**Origem:** Fluxo 4; ES-04.

**Descrição:** Obter, junto ao `Person Service`, o dado de destino necessário para executar um pagamento `PAY`, sem duplicar esse dado neste serviço.

**Critérios de aceite:**

* Disparado internamente, só para `type = PAY`, antes do envio ao provedor (parte de RF-01).
* Consulta `GET /v1/persons/{personId}/receiving-accounts`\* (assumido), Perfil `RECEIVING_READ` concedido a este serviço.
* Seleciona a conta marcada como `isPrimary` quando existir mais de uma.
* Pessoa sem nenhuma conta de recebimento cadastrada → criação do Payment falha com `422 RECEBEDOR_SEM_CONTA`\* (assumido), antes de qualquer chamada ao provedor.
* Dado obtido nunca é persistido além do escopo da chamada ao provedor em curso (BD-16).

---

## RF-05 — Recebimento de Webhook do Provedor

**Origem:** Fluxo 5; ES-05.

**Descrição:** Receber, de forma idempotente e autenticada, a notificação assíncrona do `Payment Provider` sobre o resultado de uma operação em processamento.

**Critérios de aceite:**

* `POST /v1/payments/webhooks/{provider}`, sem autenticação via `auth-service` — validação de autenticidade própria do provedor (Hotspot H02).
* Extrai `providerEventId`; se já processado (mesmo `provider` + `providerEventId`), retorna `200 OK` sem reexecutar (BD-10).
* Se novo: registra em `payment_provider_events`, localiza o Payment pelo `providerPaymentId`, dispara RF-06.
* Assinatura/autenticidade inválida → `401 WEBHOOK_INVALIDO`\*, evento não processado.
* `providerPaymentId` não encontrado → `404 PAYMENT_NAO_ENCONTRADO`\*, evento registrado para diagnóstico, sem aplicar transição.

---

## RF-06 — Atualização de Status por Confirmação do Provedor

**Origem:** Fluxo 6; ES-06.

**Descrição:** Refletir, no Payment, o resultado (aprovação, rejeição, estorno) informado pelo provedor via webhook.

**Critérios de aceite:**

* Só aplicável a Payment em `PROCESSING` (para `APPROVED`/`REJECTED`) ou `APPROVED` (para `REFUNDED`/`PARTIALLY_REFUNDED`) — qualquer outra origem rejeita a transição (BD-07).
* Transição fora do catálogo fechado (`09-domain-state-machines.md`) → rejeitada, registrada como anomalia em log/auditoria, nenhuma alteração aplicada.
* Toda transição bem-sucedida grava histórico (RF-08) e auditoria (RF-09).
* Resultado ∈ {`APPROVED`, `REJECTED`, `REFUNDED`, `PARTIALLY_REFUNDED`} dispara RF-07 (Informar Billing Service).
* `REFUNDED`/`PARTIALLY_REFUNDED` só alcançados nesta versão de forma reativa — nenhum endpoint deste serviço inicia um estorno (BD-08, Hotspot H03).
* Publica o evento de domínio correspondente para consumo interno (Auditoria) e externo (`Notification Service`).

---

## RF-07 — Informar Billing Service do Resultado

**Origem:** Fluxo 7; ES-07.

**Descrição:** Propagar ao `Billing Service` o resultado de uma movimentação financeira, para que a obrigação correspondente seja atualizada.

**Critérios de aceite:**

* Disparado ao final de RF-06, quando o resultado for `APPROVED`/`REJECTED`/`REFUNDED`/`PARTIALLY_REFUNDED`.
* Chama `POST /v1/billings/{id}/payment-events`\* (assumido, contrato já publicado por `billing-service`), autenticado como Sistema Consumidor M2M.
* Aplicável a `RECEIVE` e `PAY` igualmente (BD-01).
* Falha na chamada não reverte o Payment, já `APPROVED`/`REJECTED`/`REFUNDED` de forma definitiva neste serviço — sem retry automático nesta versão (BD-14).

---

## RF-08 — Registro de Histórico de Status

**Origem:** Fluxo 8; ES-08.

**Descrição:** Garantir rastreabilidade completa de toda mudança de status.

**Critérios de aceite:**

* Toda transição de `status` (RF-01, RF-06) grava uma linha em `payment_status_history`, na mesma transação que atualiza o Payment.
* Histórico nunca é alterado ou removido depois de criado.

---

## RF-09 — Auditoria de Operações

**Origem:** Fluxo 9; ES-09.

**Descrição:** Registrar toda operação financeira relevante.

**Critérios de aceite:**

* Toda operação de RF-01, RF-06 bem-sucedida gera um registro de auditoria com `paymentId`, `billingId`, `operation`, `application`, `actor`, `createdAt` (BD-18).
* Nenhum dado financeiro sensível (chave Pix, conta bancária, CVV) é gravado no registro de auditoria (BD-15, BD-18).
* Endpoint de consulta de auditoria não é exposto na API do MVP — fora do mapeamento 1:1 desta versão (ver seção "Fora do mapeamento 1:1", abaixo).

---

## Fora do mapeamento 1:1

Consulta de histórico de status (`GET /v1/payments/{id}/history`\*, análoga à de `billing-service`) e a consulta de eventos de provedor recebidos (`payment_provider_events`) não correspondem a nenhum dos 9 fluxos numerados (são operações de leitura administrativa, não fluxos de negócio com regra própria) — contratadas diretamente em `../contratos/17-api-contracts.md`, mesmo tratamento já dado por `billing-service`/`person-service`/`storage-service` a "Consultas Administrativas". `POST /v1/payments/{id}/cancel`\* também fica fora do mapeamento 1:1 — endpoint assumido, inferido pela combinação de Perfil `PAYMENT_CANCEL` + evento `PAYMENT_CANCELLED` + transição `PENDING → CANCELLED`, sem fluxo numerado próprio (nota de 2026-08-13, verificação: `17-api-contracts.md` seção 5 citava "RF-06" incorretamente — corrigido, já que RF-06 é "Atualização de Status por Confirmação do Provedor", sem relação com cancelamento). `POST /v1/payments/{id}/refund` também fica fora do mapeamento 1:1 desta versão — não implementado nesta versão (BD-08, Hotspot H03), mas contratado para referência futura.
