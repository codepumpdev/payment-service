# Contratos de API — Payment Service

> Cobre os fluxos já modelados em `../dominio/02-event-stories.md` (ES-01 a ES-09) e os requisitos funcionais correspondentes (`../requisitos/10-functional-requirements.md`, RF-01 a RF-09). Rotas versionadas com prefixo `/v1` (ADR-005). `GET /health` é exceção deliberada de versionamento. Onde o domínio já modelado não fixa um detalhe, este documento resolve de forma simples, marcado com **\*** e listado em "Pontos Abertos".

---

## Convenções

* Todas as rotas exigem HTTPS; corpo em JSON, exceto onde indicado.
* Erros: `{ "error": { "code": "CODIGO_DO_ERRO", "message": "Descrição legível" } }` (ADR-004) — envelope aninhado, padrão organizacional, sem desvio.
* **Autenticação:** header `Authorization: Bearer <JWT>`, emitido por `auth-service` — Token de Serviço M2M. Este serviço nunca emite/valida credenciais próprias (BD-04, ADR-001). **Exceção:** o webhook (seção 4, abaixo) não usa JWT — mecanismo de autenticidade próprio do provedor.
* **Perfis** (BD-04): `PAYMENT_READ`, `PAYMENT_CREATE`, `PAYMENT_CANCEL`, `PAYMENT_REFUND`. Falta de Perfil → `403 PERFIL_INSUFICIENTE`.
* **Padrão de resposta** (ADR-004): `GET` recurso único → corpo direto; `GET` lista → `{ "content": [...], "page": 0, "size": 20, "totalElements": 0, "totalPages": 0 }`; `POST` criação → `201 Created` + `Location` + corpo (exceto reenvio de `idempotencyKey`, que responde `200 OK`); `POST /cancel` → `200 OK` + corpo atualizado. Nenhum `DELETE` de Payment (ADR-006).
* **Paginação\*:** `page` (0-based, padrão `0`), `size` (padrão `20`, máximo `100`).
* **Formato de data/hora:** ISO 8601 com timezone\*.
* **Correlation ID:** header `X-Correlation-ID` aceito em toda requisição; gerado quando ausente; propagado a `Billing Service`/`Payment Provider`/`Notification Service` (BD-19).

---

## 1. Criação de Payment — ES-01, RF-01

`POST /v1/payments` — Perfil `PAYMENT_CREATE`.

**Request — recebimento (`RECEIVE`):**
```json
{
  "type": "RECEIVE",
  "billingId": "650e8400-e29b-41d4-a716-446655440000",
  "amount": 150.90,
  "currency": "BRL",
  "method": "PIX",
  "idempotencyKey": "ORDER-123456-PAYMENT"
}
```

**Request — pagamento (`PAY`):**
```json
{
  "type": "PAY",
  "billingId": "750e8400-e29b-41d4-a716-446655440000",
  "amount": 500.00,
  "currency": "BRL",
  "method": "PIX",
  "idempotencyKey": "ORDER-123456-PAYOUT"
}
```

Todos os campos são obrigatórios (BD-02, BD-03, BD-05, BD-06, BD-09, BD-11).

**Response — `201 Created`, `Location: /v1/payments/{id}`:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "RECEIVE",
  "billingId": "650e8400-e29b-41d4-a716-446655440000",
  "amount": 150.90,
  "currency": "BRL",
  "method": "PIX",
  "status": "PROCESSING",
  "provider": "PROVIDER_A",
  "providerPaymentId": "PIX-123456",
  "paymentData": { "qrCode": "00020126...", "copyPaste": "00020126..." },
  "createdAt": "2026-08-12T20:00:00-03:00",
  "updatedAt": "2026-08-12T20:00:00-03:00"
}
```

`provider`/`providerPaymentId`/`paymentData` só aparecem preenchidos se o envio síncrono ao provedor foi aceito (`status = PROCESSING`); se o envio falhou, `status = PENDING` e esses campos vêm nulos/ausentes. Formato exato de `paymentData` depende do provedor real (Hotspot H01) — o exemplo acima (`qrCode`/`copyPaste`) é ilustrativo, para Pix.

**Response — `200 OK`** (mesmo corpo), quando `idempotencyKey` já existir na mesma `application` — Payment já existente é retornado, sem criar duplicata.

**Erros:**

| HTTP | `error.code` | Motivo |
|---|---|---|
| 400 | `VALIDACAO_FALHOU` | campo obrigatório ausente, ou `type` fora de `{RECEIVE, PAY}` |
| 400 | `MOEDA_NAO_SUPORTADA` | `currency` diferente de `BRL` (BD-05) |
| 400 | `METODO_NAO_SUPORTADO` | `method` diferente de `PIX` nesta versão (BD-06) |
| 400 | `IDEMPOTENCY_KEY_OBRIGATORIA` | `idempotencyKey` ausente |
| 404 | `COBRANCA_NAO_ENCONTRADA` | `billingId` inexistente no `Billing Service` |
| 409 | `VALOR_EXCEDE_COBRANCA` | `amount` ultrapassa o valor disponível da cobrança (BD-11) |
| 422 | `RECEBEDOR_SEM_CONTA`\* | `type = PAY` e a Pessoa recebedora não tem conta de recebimento cadastrada (ES-04) |
| 401 | `NAO_AUTENTICADO` | token ausente/inválido/expirado |
| 403 | `PERFIL_INSUFICIENTE` | falta `PAYMENT_CREATE` |

---

## 2. Consulta de Payment por Identificador — ES-02, RF-02

`GET /v1/payments/{id}` — Perfil `PAYMENT_READ`.

**Response — `200 OK`:** mesmo formato da criação (seção 1), sem `paymentData` depois que o Payment sai de `PROCESSING`.

**Erros:** `404 PAYMENT_NAO_ENCONTRADO`; `401`/`403` como acima.

---

## 3. Consulta de Payments por Cobrança — ES-03, RF-03

`GET /v1/payments?billingId={billingId}` — Perfil `PAYMENT_READ`. Filtros adicionais opcionais: `status`, `page`, `size`.

**Response — `200 OK`:**
```json
{ "content": [ /* payments */ ], "page": 0, "size": 20, "totalElements": 3, "totalPages": 1 }
```

Lista vazia (`200 OK`), nunca `404`, quando nenhum Payment corresponder. Ordenado por `createdAt` (mais antigo primeiro), para refletir a ordem cronológica de tentativas (BD-12).

---

## 4. Webhook do Provedor — ES-05, RF-05

`POST /v1/payments/webhooks/{provider}` — **sem JWT**, mecanismo de autenticidade próprio do provedor (Hotspot H02).

**Request (assumido\*, formato ilustrativo — depende do provedor real, Hotspot H01):**
```json
{
  "providerEventId": "PROVIDER_EVENT_123456",
  "providerPaymentId": "PIX-123456",
  "eventType": "PAYMENT_APPROVED",
  "amount": 150.90,
  "occurredAt": "2026-08-12T20:05:00-03:00"
}
```

`eventType` ∈ `PAYMENT_APPROVED`, `PAYMENT_REJECTED`, `PAYMENT_REFUNDED`, `PAYMENT_PARTIALLY_REFUNDED`\* (assumido, ver Hotspot H03).

**Response — `200 OK`:** sem corpo relevante — confirma recebimento ao provedor, independentemente de o evento já ter sido processado antes (idempotência, BD-10).

**Erros:**

| HTTP | `error.code` | Motivo |
|---|---|---|
| 401 | `WEBHOOK_INVALIDO`\* | assinatura/autenticidade inválida (Hotspot H02) |
| 400 | `EVENTO_INVALIDO`\* | `providerEventId` ausente ou payload malformado |
| 404 | `PAYMENT_NAO_ENCONTRADO`\* | `providerPaymentId` não corresponde a nenhum Payment conhecido — evento registrado em `payment_provider_events` para diagnóstico, sem aplicar transição |

---

## 5. Cancelamento de Payment — Fora do Mapeamento 1:1 (transição `PENDING → CANCELLED`)

`POST /v1/payments/{id}/cancel`\* — Perfil `PAYMENT_CANCEL`. **Endpoint assumido** — não citado literalmente pelo documento funcional; inferido pela combinação de Perfil `PAYMENT_CANCEL` + evento `PAYMENT_CANCELLED` + transição `PENDING → CANCELLED` do diagrama da seção 10.

**Request (opcional):**
```json
{ "reason": "Solicitado pelo cliente antes do envio ao provedor" }
```

**Response — `200 OK`:** Payment com `status: "CANCELLED"`.

**Erros:**

| HTTP | `error.code` | Motivo |
|---|---|---|
| 409 | `PAYMENT_NAO_CANCELAVEL`\* | `status` diferente de `PENDING` (só permitido antes do envio ao provedor) |
| 404 | `PAYMENT_NAO_ENCONTRADO` | `id` inexistente |
| 403 | `PERFIL_INSUFICIENTE` | falta `PAYMENT_CANCEL` |

---

## 6. Estorno — Contrato Documentado, Não Implementado Nesta Versão

`POST /v1/payments/{id}/refund` — Perfil `PAYMENT_REFUND`. **Fora de escopo da primeira versão** (BD-08, ADR-016, Hotspot H03) — contrato registrado aqui só para referência futura, endpoint não ativo nesta versão (`501`\* ou rota inexistente, decisão de implementação a confirmar).

**Request — estorno total (contrato futuro):**
```json
{ "amount": 150.90, "reason": "CANCELLED_ORDER" }
```

**Request — estorno parcial (contrato futuro, versão posterior mesmo ao estorno total — seção 24 do documento funcional):**
```json
{ "amount": 50.00, "reason": "PARTIAL_REFUND" }
```

Transições associadas (futuras): `APPROVED → REFUNDED` (total) ou `APPROVED → PARTIALLY_REFUNDED` (parcial).

---

## 7. Consulta de Histórico de Status — ES-08

`GET /v1/payments/{id}/history`\* — Perfil `PAYMENT_READ`. Endpoint assumido, análogo ao já documentado por `billing-service`.

**Response — `200 OK`:**
```json
{
  "content": [
    { "fromStatus": null, "toStatus": "PENDING", "reason": null, "createdAt": "2026-08-12T20:00:00-03:00" },
    { "fromStatus": "PENDING", "toStatus": "PROCESSING", "reason": null, "createdAt": "2026-08-12T20:00:01-03:00" },
    { "fromStatus": "PROCESSING", "toStatus": "APPROVED", "reason": null, "providerEventId": "PROVIDER_EVENT_123456", "createdAt": "2026-08-12T20:05:00-03:00" }
  ]
}
```

Sem paginação nesta versão (histórico de um único Payment, volume tipicamente pequeno) — assumido\*.

---

## Pontos Abertos

* **Formato exato de `paymentData` na criação (seção 1)** e **payload exato do webhook (seção 4)** — dependem do provedor real (Hotspot H01) e do mecanismo de autenticidade (Hotspot H02).
* **Contrato de consulta ao `Billing Service`/`Person Service`** — reaproveita endpoints já publicados por aqueles serviços, ver `12-acceptance-criteria.md`, Valores Assumidos.
* **Endpoint de cancelamento (seção 5)** — inferido, não literal no documento funcional.
* **Endpoint de estorno (seção 6)** — contrato documentado, fora de escopo de implementação nesta versão (Hotspot H03).
