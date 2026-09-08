# Contratos de API — Payment Service

> **Desatualizado em 2026-09-07 — o conceito de Contexto foi removido da plataforma.**
>
> O que neste documento descreve Contexto **não vale mais**: a rota `POST /internal/resetContext`, que não existe mais, e o que o texto diga sobre o Contexto chegar pela identidade autenticada.
>
> A separação de dados passou a ser **por serviço**: cada serviço tem um banco,
> com endereço na configuração dele, conhecido na partida. O padrão está em
> `codepump/docs/padrao-desenvolvimento.md` §28; o registro do que o Contexto
> era, do que custou e do que se perdeu ao retirá-lo está em
> `codepump/docs/contexto-o-que-foi-e-por-que-saiu.md`.
>
> **O texto abaixo fica como estava.** Ele descreve decisões reais, tomadas por
> razões reais, e reescrevê-lo apagaria que a ideia já foi tentada — o resto do
> documento, que não fala de Contexto, continua valendo.


> Cobre os fluxos já modelados em `../dominio/02-event-stories.md` (ES-01 a ES-09) e os requisitos funcionais correspondentes (`../requisitos/10-functional-requirements.md`, RF-01 a RF-09). Rotas versionadas com prefixo `/v1` (ADR-005). `GET /health` e `GET /ready` (seção 8) seguem, ambos, a exceção de versionamento — convenção organizacional de health-check/readiness-check (`padrao-desenvolvimento.md`, seção 12; ADR-019). Onde o domínio já modelado não fixa um detalhe, este documento resolve de forma simples, marcado com **\*** e listado em "Pontos Abertos".

---

## Convenções

* Todas as rotas exigem HTTPS; corpo em JSON, exceto onde indicado.
* Erros: envelope alinhado ao `ErrorResponse` canônico da `codepump-lib` (ADR-004; `padrao-desenvolvimento.md` seção 4 e 18) — formato plano `timestamp`/`status`/`code`/`message`/`path`?/`correlationId`?/`errors`?[]; identificação pelo `code`, nunca pela `message`:
  ```json
  {
    "timestamp": "2026-08-14T14:30:00Z",
    "status": "BAD_REQUEST",
    "code": "VALIDACAO_FALHOU",
    "message": "A requisição contém campos inválidos.",
    "path": "/v1/payments",
    "correlationId": "7f4a8b2c"
  }
  ```
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
| 403 | `RECURSO_NAO_PERMITIDO_NO_PLANO` | operação em nome de usuário (`X-User` + `SERVICE JWT`) cujo plano (`profile.plan` do único `profile` no `USER JWT`) **não permite** o recurso externo `PAYMENT` (`FREE`) — validado **antes** de qualquer efeito (ADR-022, seção 26.10; ver seção 10) |
| 403 | `LIMITE_PLANO_ATINGIDO` | operação em nome de usuário `FREE` (`X-User` + `SERVICE JWT`) cujo titular já atingiu `payment.maxRecords` (secundário ao gating de recurso; ver seção 10) |

**Headers — operação em nome de usuário (seção 9.4):**
```http
POST /v1/payments
Authorization: Bearer <SERVICE_JWT>   # a aplicação chamadora (executor, roles sobre PAYMENT_SERVICE — BD-24)
X-User: <USER_JWT>                    # o usuário em nome de quem a operação corre (identidade + profile único: app/roles/plan)
```
O `USER JWT` é específico de uma aplicação (um único `profile`); o contexto de aplicação e o plano vêm de `profile.app`/`profile.plan` no token assinado (seção 9.3/9.4) — não há header `X-User-App`.

Operação **sistema-a-sistema** (sem usuário) traz **só** `Authorization: Bearer <SERVICE_JWT>` — nunca `X-User`. No **encadeamento** de uma mesma operação, o `X-User` permanece fixo; só o `Authorization` muda para o `SERVICE_JWT` de cada executor.

> **Gating de plano (em nome de usuário) — ADR-022/BD-21, ver seção 10.** Quando a criação chega em **contexto de usuário** (reconhecido por `X-User: <USER_JWT>` + `Authorization: <SERVICE_JWT>`, seção 9.4), **antes** da validação de cobrança (BD-11), da obtenção do recebedor (BD-16) e do envio ao provedor (BD-13), o serviço valida o **recurso externo `PAYMENT`** contra o plano lido **direto** de `profile.plan` do único `profile` no **`USER JWT`** (`X-User`; `profile.app` diz a aplicação do contexto, confiável por estar no JWT assinado): `FREE` → `403 RECURSO_NAO_PERMITIDO_NO_PLANO` (nenhum Payment criado, nenhuma chamada externa feita); `PRO`/`MAX` → prossegue. Só então aplica o **limite** (`FREE` → `payment.maxRecords` por titular `owner_user_id` = `sub` do `USER JWT`, excedente → `403 LIMITE_PLANO_ATINGIDO`) e define `purge_at`. Operações **sistema-a-sistema** (só `SERVICE JWT`, sem `X-User`) não passam por esse gating.

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

## 8. Health Check, Readiness Check e Identificação de Build — ADR-019

Padrão organizacional (`padrao-desenvolvimento.md`, seção 12), obrigatório para todo serviço da empresa — ver ADR-019 para o raciocínio completo e a tabela de dependências específicas deste serviço (incluindo o Hotspot H04 sobre `Billing Service`/`Person Service`).

### `GET /health`

Sem autenticação; exceção de versionamento. Liveness — nunca consulta PostgreSQL, `auth-service`, `Billing Service`, `Person Service`, `Notification Service`, `Payment Provider` ou OpenBao.

**Response — 200 OK:**
```json
{
  "status": "UP",
  "branch": "main",
  "commit": "ba996ad8715",
  "buildDate": "2026-08-13T14:30:00-03:00"
}
```

**Response — 503 Service Unavailable:** processo não consegue responder normalmente.

### `GET /ready`

Sem autenticação. Readiness — verifica as dependências obrigatórias deste serviço (PostgreSQL, banco `payment`, ADR-018; `auth-service`, via `GET /health` dele). `Billing Service`, `Person Service`, `Payment Provider`, `Notification Service`, OpenBao e RabbitMQ **não** entram neste check (ver ADR-019 para o raciocínio completo, incluindo o Hotspot H04).

**Response — 200 OK:**
```json
{
  "status": "READY",
  "responseTime": 31,
  "dependencies": {
    "database": { "status": "UP", "responseTime": 8 },
    "auth-service": { "status": "UP", "responseTime": 22 }
  }
}
```

**Response — 503 Service Unavailable:**
```json
{
  "status": "NOT_READY",
  "responseTime": 5000,
  "dependencies": {
    "database": { "status": "DOWN", "responseTime": null, "error": "TIMEOUT" },
    "auth-service": { "status": "UP", "responseTime": 19 }
  }
}
```

---

## 9. Expurgo de Pagamentos `PENDING` Órfãos (Endpoint Interno) — ADR-021

Expurgo por retenção — endpoint **padronizado** `POST /internal/purge`, idêntico em nome entre todos os serviços (`padrao-desenvolvimento.md`, seção 5).

`POST /internal/purge`

**Prefixo `/internal/*`, sem `/v1`** (convenção de infraestrutura Nginx, `padrao-desenvolvimento.md`, seção 14.3) — nunca exposto pelo Nginx, alcançável somente pela rede interna do Docker Compose.

**Autenticação:** Bearer JWT — Token de Serviço M2M, perfil `SCHEDULER` (`padrao-desenvolvimento.md`, seções 9.1/9.3), obtido pelo `scheduler-service` junto a `auth-service`. Nunca `ADMIN`.

**Request:** sem corpo (o disparo é "é hora, execute", sem payload de negócio).

**Lógica executada** (ADR-021): seleciona candidatos `status = PENDING` com `createdAt < (agora − minPendingAge)` (`minPendingAge` padrão 24h\*, configurável `payment.purge.minPendingAgeHours`); para cada candidato, **consulta o `billing-service` (M2M)** se a Cobrança `billingId` existe. Executa `DELETE` físico **somente** dos que o `billing-service` confirma **inexistentes**. Se o `billing-service` estiver indisponível/inconclusivo, o candidato é **poupado** (não expurgado) e contado em `billingUnavailableSkipped`. Registra auditoria (`operation = PAYMENT_PURGE`, sem dado financeiro). **Nunca** remove registros de auditoria; nunca expurga `APPROVED`/`REJECTED`/`CANCELLED`/`REFUNDED`.

Este mesmo endpoint tem um **segundo motivo** de expurgo — a **retenção `FREE`** (seção 26.8 do padrão, ADR-022/BD-21). Na mesma execução, além dos órfãos-`PENDING` acima, seleciona os `payments` com `purge_at <= now()` (critério **temporal**, **não** relacional — **não** consulta o `billing-service`, independe do status) e, para cada um, remove primeiro os relacionados (`payment_status_history`, `payment_provider_events`) e depois o próprio Payment, respeitando o `ON DELETE RESTRICT` pela ordem de remoção. **Nunca** um endpoint separado (seção 26.8). A resposta inclui o contador `retentionPurged`; `paymentsPurged` é o total dos dois motivos. No MVP o motivo de retenção fica inerte (nenhum Payment `FREE` é criado, pois `FREE` não permite o recurso `PAYMENT` — ADR-022). Ver ADR-022 e a seção 10.

**Response — 200 OK:**
```json
{
  "status": "SUCCESS",
  "executedAt": "2026-08-15T03:00:00-03:00",
  "candidatesEvaluated": 340,
  "billingUnavailableSkipped": 5,
  "orphanPendingPurged": 22,
  "retentionPurged": 0,
  "paymentsPurged": 22
}
```

Idempotente — nenhum elegível (por nenhum dos dois motivos) → `200 OK` com `paymentsPurged: 0`, sem erro.

**Erros:**

| HTTP | `error.code` | Motivo |
|---|---|---|
| 401 | `NAO_AUTENTICADO` | token ausente/inválido/expirado |
| 403 | `PERFIL_INSUFICIENTE` | chamador sem o perfil `SCHEDULER` |

---

## 10. Planos, Recurso Externo `PAYMENT`, Retenção e Expurgo — ADR-022 (padrão seção 26)

O `payment-service` é **aplicação alvo**: ao receber uma operação **em nome de um usuário** (dois tokens, seção 9.4 — `SERVICE JWT` no `Authorization` + `USER JWT` no `X-User`), lê o `plan` **direto** de `profile.plan` do único `profile` do **`USER JWT`** (o token é específico de uma aplicação — `profile.app` diz o contexto; seção 9.3/26.2) e o `sub` do usuário (via `TokenClaims` da `codepump-lib`), e aplica **recurso externo/limite/retenção** desse plano. Não há header `X-User-App` nem o erro `403 CONTEXTO_APLICACAO_INVALIDO` — o contexto de aplicação vem de `profile.app`. `PAYMENT` é o **recurso externo** exemplo da seção 26.10 (`FREE` não permite; `PRO`/`MAX` permitem). Ver ADR-022/BD-21.

### 10.1 Consulta de Planos — `GET /plans`

Leitura **pública** das configurações de plano deste serviço, **incluindo os recursos externos por plano**. Sem dado interno desnecessário (seção 26.4).

**Response — 200 OK:**
```json
{
  "plans": [
    { "plan": "FREE", "externalResources": [{ "resource": "PAYMENT", "allowed": false }], "limits": { "payment.maxRecords": 20 }, "retentionDays": 30 },
    { "plan": "PRO",  "externalResources": [{ "resource": "PAYMENT", "allowed": true }],  "limits": { "payment.maxRecords": null }, "retentionDays": null },
    { "plan": "MAX",  "externalResources": [{ "resource": "PAYMENT", "allowed": true }],  "limits": { "payment.maxRecords": null }, "retentionDays": null }
  ]
}
```

`payment.maxRecords = 20`\* e `retentionDays = 30`\* são valores assumidos/configuráveis; `PAYMENT` não permitido em `FREE` é decidido pela spec (seção 26.10), não assumido.

### 10.2 Configuração de Planos — `/config/plans`

Administração dos valores acima (recursos externos, limites, retenção), sob a API de Configuração já adotada por este serviço (**ADR-020**, `GET /admin/config`), perfil **`ADMIN`** (seção 9.1 do padrão). Validação no backend; auditoria de mudança (`AuditEvent`, `resource = CONFIG`); nunca expõe sensíveis. Sem API de consulta paralela — usa os `GET` padronizados.

### 10.3 Atualização de Plano do Usuário — `POST /internal/users/{userId}/plan`

Endpoint **interno** (M2M, Token de `SERVICE`), chamado pela aplicação de pagamento no fluxo de upgrade/downgrade. **Prefixo `/internal/*`, sem `/v1`**, nunca exposto pelo Nginx (seção 14.3). **O chamador não informa quais registros** — o serviço decide internamente.

**Request:** `{ "plan": "PRO" }`

**Comportamento:**
- **Upgrade** (`FREE → PRO`/`MAX`): atualiza o plano aplicável ao titular `userId`; localiza os Payments do titular com `purge_at IS NOT NULL`; **zera `purge_at`**; mantém os dados permanentes.
- **Downgrade** (`PRO`/`MAX → FREE`): **não** atribui `purge_at` a registros existentes (MVP).

**Response — 200 OK:** `{ "userId": "...", "plan": "PRO", "recordsReleased": 0 }`

**Erros:** `400 PLANO_INVALIDO` (fora de `FREE`/`PRO`/`MAX`); `401 NAO_AUTENTICADO`; `403 PERFIL_INSUFICIENTE`.

### 10.4 Expurgo de Retenção — dentro do `POST /internal/purge` (seção 9)

O expurgo de retenção `FREE` (`payments.purge_at <= now()`) **não** tem endpoint próprio — é o **segundo motivo** do `POST /internal/purge` já documentado na **seção 9** (seção 26.8: nunca um endpoint separado). Ver a seção 9.

### Resumo de Rotas (planos/expurgo)

| Método | Rota | Perfil |
|---|---|---|
| GET | `/plans` | Público (leitura) |
| POST | `/internal/users/{userId}/plan` | Bearer (`SERVICE`, M2M) |
| POST | `/internal/purge` | Bearer (`SCHEDULER`, M2M) — ver seção 9 (órfão-`PENDING` + retenção `FREE`) |

> **Nota (criação de Payment, seção 1):** ao criar Payment em contexto de usuário (`X-User` + `SERVICE JWT`, seção 9.4), aplica-se o gating do recurso externo `PAYMENT` contra o plano lido **direto** de `profile.plan` do único `profile` no `USER JWT` (`FREE` → `403 RECURSO_NAO_PERMITIDO_NO_PLANO`), depois o **limite** (`FREE` → `payment.maxRecords` por titular, excedente → `403 LIMITE_PLANO_ATINGIDO`), e define-se `purge_at` para titular `FREE` (`created_at + retentionDays`). Ver ADR-022/BD-21.

---

## Pontos Abertos

* **Formato exato de `paymentData` na criação (seção 1)** e **payload exato do webhook (seção 4)** — dependem do provedor real (Hotspot H01) e do mecanismo de autenticidade (Hotspot H02).
* **Contrato de consulta ao `Billing Service`/`Person Service`** — reaproveita endpoints já publicados por aqueles serviços, ver `12-acceptance-criteria.md`, Valores Assumidos.
* **Endpoint de cancelamento (seção 5)** — inferido, não literal no documento funcional.
* **Endpoint de estorno (seção 6)** — contrato documentado, fora de escopo de implementação nesta versão (Hotspot H03).
* **`Billing Service`/`Person Service` como dependências obrigatórias do `/ready` (seção 8)** — Hotspot H04, ver ADR-019.

---

## Resumo de Rotas

| Método | Rota | Auth | Seção |
|---|---|---|---|
| POST | `/v1/payments` | Bearer (`PAYMENT_CREATE`) | 1 |
| GET | `/v1/payments/{id}` | Bearer (`PAYMENT_READ`) | 2 |
| GET | `/v1/payments?billingId=...` | Bearer (`PAYMENT_READ`) | 3 |
| POST | `/v1/payments/webhooks/{provider}` | Mecanismo próprio do provedor (H02) | 4 |
| POST | `/v1/payments/{id}/cancel` | Bearer (`PAYMENT_CANCEL`) | 5 |
| POST | `/v1/payments/{id}/refund` | Bearer (`PAYMENT_REFUND`) — fora de escopo v1 | 6 (H03) |
| GET | `/v1/payments/{id}/history` | Bearer (`PAYMENT_READ`) | 7 |
| GET | `/health` | — | 8 (ADR-019) |
| GET | `/ready` | — | 8 (ADR-019) |
| POST | `/internal/purge` | Bearer (`SCHEDULER`, M2M) | 9 (ADR-021 órfão-`PENDING` + ADR-022 retenção `FREE`) |
| GET | `/plans` | Público (leitura) | 10 (ADR-022) |
| POST | `/internal/users/{userId}/plan` | Bearer (`SERVICE`, M2M) | 10 (ADR-022) |

Fora deste versionamento (ADR-005): `GET /health`, `GET /ready` (seção 8), `POST /internal/purge` e `POST /internal/users/{userId}/plan` (prefixo `/internal/*`, `padrao-desenvolvimento.md` seção 14.3). `GET /plans` é leitura pública das configurações de plano (seção 26.4) — sem `/v1`, como os demais endpoints de plano do padrão.

---

## Invalidação do cache de Contexto — `POST /internal/resetContext`

Rota **interna** (M2M, §9.3), obrigatória em todo serviço que usa o `ContextResolver` (`codepump/docs/padrao-desenvolvimento.md` §28.10). Não é exposta pelo Nginx e não é operação de negócio.

```http
POST /internal/resetContext
→ 204 No Content
```

**Sem parâmetros e sem corpo.** Descarta **todas** as resoluções de Contexto mantidas por este processo, fecha os pools PostgreSQL associados a elas e deixa a próxima utilização de cada Contexto responsável por uma nova resolução no `context-service`.

Não pré-carrega nada, não reconstrói o cache, não altera dado, não fala com o `context-service` durante o reset e não reinicia o processo. Se depois do reset só `prod_2` for usado, só `prod_2` volta ao cache.

**A rota não aceita Contexto do cliente** — não existe `resetContext/{context}`, e a ausência é deliberada (§28.10): uma resolução é resultado de um estado do catálogo, e descartar meio estado deixa no cache justamente o que ninguém lembrou de invalidar.

**A invalidação é local ao processo.** Resetar uma instância não invalida as outras: cobrir todas as instâncias dos serviços afetados é do procedimento de alteração de infraestrutura, que executa nesta ordem — alterar a infraestrutura, atualizar o `context-service`, resetar os serviços, validar o acesso.

> Implementação: a rota chama `resolver.Reset()` da `codepump-lib` e responde `204`. O `Reset` **bloqueia até os pools antigos fecharem**, e uma requisição que já estava em andamento falha ao usar a resolução descartada — refeita na tentativa seguinte.
