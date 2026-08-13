# Event Stories — Payment Service

> Uma Event Story por fluxo numerado de `01-event-storming-big-picture.md`. Mesmo formato de `billing-service`/`person-service`/`storage-service`.

---

## ES-01 — Criação de Payment

**Objetivo:** transformar uma cobrança já existente no `Billing Service` em uma tentativa concreta de movimentação financeira, nos dois sentidos (`RECEIVE`/`PAY`).

**Atores:** Sistema Consumidor.

**Fluxo Principal:**

1. Sistema Consumidor chama `POST /v1/payments` com `type`, `billingId`, `amount`, `currency`, `method`, `idempotencyKey`.
2. Payment API verifica se já existe um Payment com o mesmo `idempotencyKey` no contexto da mesma aplicação chamadora (BD-09).
3. Se já existir: retorna o Payment já criado (`200`, não `201`), sem criar duplicata.
4. Se não existir: valida o payload (`type` ∈ {`RECEIVE`, `PAY`}, `currency = BRL`, `method` implementado).
5. Consulta o `Billing Service` (`GET /v1/billings/{billingId}`\*, assumido) para confirmar que a cobrança existe e que `amount` não ultrapassa o valor disponível (BD-11).
6. Cria o Payment com `status = PENDING`.
7. Se `type = PAY`: dispara ES-04 (Obtenção de Dados do Recebedor) antes do envio ao provedor.
8. Envia a operação ao provedor configurado (BD-13). Se aceito: transiciona para `PROCESSING`, registra histórico e auditoria (`PAYMENT_PROCESSING`). Se falhar: Payment permanece `PENDING`, sem retry automático nesta versão.
9. Registra histórico (`fromStatus = null → toStatus = PENDING`) e auditoria (`PAYMENT_CREATED`).
10. Retorna `201 Created`, `Location: /v1/payments/{id}`, corpo com o recurso criado — incluindo os dados necessários para o pagador concluir a operação, quando aplicável (ex.: QR Code Pix, formato dependente do provedor, Hotspot H01).

**Policies:** se `type = PAY` e a Pessoa recebedora não tiver conta de recebimento cadastrada, a criação falha antes de qualquer chamada ao provedor (ES-04).

**Regras:** BD-02, BD-04, BD-05, BD-06, BD-09, BD-11, BD-13.

**Alternativas:**

* Campo obrigatório ausente → `400 VALIDACAO_FALHOU`.
* `currency` diferente de `BRL` → `400 MOEDA_NAO_SUPORTADA`.
* `method` não implementado → `400 METODO_NAO_SUPORTADO`.
* `billingId` inexistente → `404 COBRANCA_NAO_ENCONTRADA`.
* `amount` ultrapassa o valor disponível da cobrança → `409 VALOR_EXCEDE_COBRANCA`.
* `idempotencyKey` ausente → `400 IDEMPOTENCY_KEY_OBRIGATORIA`.
* Token ausente/inválido → `401 NAO_AUTENTICADO`; Perfil `PAYMENT_CREATE` ausente → `403 PERFIL_INSUFICIENTE`.

---

## ES-02 — Consulta de Payment por Identificador

**Objetivo:** permitir que um Sistema Consumidor recupere o estado corrente de um pagamento já criado.

**Atores:** Sistema Consumidor.

**Fluxo Principal:**

1. Sistema Consumidor chama `GET /v1/payments/{id}`.
2. Payment API localiza o Payment.
3. Retorna `200 OK` com todos os campos, exceto dado interno de auditoria.

**Regras:** nenhuma regra de negócio própria — leitura direta.

**Alternativas:**

* `id` inexistente → `404 PAYMENT_NAO_ENCONTRADO`.
* Perfil `PAYMENT_READ` ausente → `403 PERFIL_INSUFICIENTE`.

---

## ES-03 — Consulta de Payments por Cobrança

**Objetivo:** permitir localizar todas as tentativas de pagamento relacionadas a uma cobrança — necessário para tentativa recusada, nova tentativa, pagamento parcial, múltiplos pagamentos ou estorno (seção 21 do documento funcional).

**Atores:** Sistema Consumidor (tipicamente `Billing Service`).

**Fluxo Principal:**

1. Sistema Consumidor chama `GET /v1/payments?billingId={billingId}`, opcionalmente com `status`, `page`, `size`.
2. Payment API filtra por `billing_id`.
3. Retorna `200 OK` com a lista (paginada) de Payments correspondentes, ordenados por `createdAt`.

**Regras:** RF-03.

**Alternativas:**

* Nenhum Payment encontrado → `200 OK` com lista vazia (nunca `404` — é uma consulta de coleção).
* Perfil `PAYMENT_READ` ausente → `403 PERFIL_INSUFICIENTE`.

---

## ES-04 — Obtenção de Dados do Recebedor (`PAY`)

**Objetivo:** obter, junto ao `Person Service`, o dado de destino necessário para executar um pagamento `PAY`, sem duplicar esse dado no `Payment Service`.

**Atores:** Payment Service (interno, disparado pelo passo 7 de ES-01).

**Fluxo Principal:**

1. Payment API identifica o `personId` do recebedor (a partir do `billingId` — o recebedor de uma cobrança `PAYABLE` já é conhecido pelo `Billing Service`, repassado na criação do Payment ou consultado junto à cobrança, assumido\*).
2. Payment API chama `GET /v1/persons/{personId}/receiving-accounts`\* (assumido, Perfil `RECEIVING_READ` concedido a este serviço via `auth-service`).
3. Person Service retorna a lista de contas de recebimento cadastradas.
4. Payment API seleciona a conta marcada como `isPrimary` (mesma convenção já usada por `person-service`, BD-04 daquele serviço).
5. Payment API usa o dado só durante a chamada ao provedor (passo 8 de ES-01) — nunca persiste chave Pix/conta bancária em nenhuma tabela própria (BD-16).

**Policies:** nenhuma automação adicional — resultado consumido imediatamente pelo passo seguinte de ES-01.

**Regras:** BD-16.

**Alternativas:**

* Pessoa sem nenhuma conta de recebimento cadastrada → criação do Payment falha, `422 RECEBEDOR_SEM_CONTA`\* (assumido, ver Valores Assumidos), nenhuma chamada ao provedor é feita.
* `Person Service` indisponível → criação do Payment falha, `503`\* ou erro equivalente (assumido), sem retry automático nesta versão.

---

## ES-05 — Recebimento de Webhook do Provedor

**Objetivo:** permitir que o `Payment Provider` informe, de forma assíncrona, o resultado de uma operação em processamento.

**Atores:** Payment Provider (externo).

**Fluxo Principal:**

1. Payment Provider chama `POST /v1/payments/webhooks/{provider}` com o payload específico do provedor (Hotspot H01).
2. Payment API valida a autenticidade da requisição — assinatura/segredo do provedor (Hotspot H02).
3. Payment API extrai `providerEventId` e verifica se já foi processado, consultando `payment_provider_events` (BD-10).
4. Se já processado: retorna `200 OK` sem reexecutar a operação.
5. Se novo: registra o evento em `payment_provider_events` (`status = RECEIVED`), localiza o Payment pelo `providerPaymentId`, e dispara ES-06.
6. Após processar, atualiza `payment_provider_events.status` e `processed_at`.

**Policies:** nenhum webhook é processado duas vezes, mesmo sob reenvio do provedor (BD-10).

**Regras:** BD-10, Hotspot H01, Hotspot H02.

**Alternativas:**

* Assinatura inválida → `401 WEBHOOK_INVALIDO`\*, evento não é processado nem registrado como recebido com sucesso.
* `providerPaymentId` não encontrado → `404 PAYMENT_NAO_ENCONTRADO`\*, evento registrado em `payment_provider_events` para diagnóstico, sem aplicar transição.
* `providerEventId` ausente no payload → `400 EVENTO_INVALIDO`\*.

---

## ES-06 — Atualização de Status por Confirmação do Provedor

**Objetivo:** refletir, no Payment, o resultado (aprovação, rejeição, estorno) informado pelo provedor.

**Atores:** Payment Service (interno, disparado pelo passo 5 de ES-05).

**Fluxo Principal:**

1. Payment API valida que a transição solicitada pelo evento do provedor é permitida pela máquina de estados fechada (BD-07, `09-domain-state-machines.md`).
2. Se permitida: aplica a transição (`PROCESSING → APPROVED`, `PROCESSING → REJECTED`, `APPROVED → REFUNDED`, `APPROVED → PARTIALLY_REFUNDED`).
3. Registra histórico (`payment_status_history`) e auditoria, na mesma transação.
4. Se resultado ∈ {`APPROVED`, `REJECTED`, `REFUNDED`, `PARTIALLY_REFUNDED`}: dispara ES-07 (Informar Billing Service).
5. Publica o evento de domínio correspondente (`PAYMENT_APPROVED`/`PAYMENT_REJECTED`/`PAYMENT_REFUNDED`/`PAYMENT_PARTIALLY_REFUNDED`\*) para consumo interno (Auditoria) e externo (`Notification Service`, seção 27 do documento funcional).

**Policies:** `REFUNDED`/`PARTIALLY_REFUNDED` só são alcançados nesta versão de forma reativa, por webhook do provedor — nenhum endpoint deste serviço inicia um estorno nesta versão (Hotspot H03).

**Regras:** BD-06, BD-07, BD-08, Hotspot H03.

**Alternativas:**

* Transição não permitida pela máquina de estados (ex.: `APPROVED → PENDING`) → evento rejeitado, registrado em log/auditoria como anomalia, nenhuma transição aplicada.
* Payment já em estado terminal incompatível → mesma rejeição acima.

---

## ES-07 — Informar Billing Service do Resultado

**Objetivo:** propagar ao `Billing Service` o resultado de uma movimentação financeira, para que a obrigação correspondente seja atualizada.

**Atores:** Payment Service (interno, disparado pelo passo 4 de ES-06).

**Fluxo Principal:**

1. Payment API monta o payload de resultado (`event`, `amount`, `paidAt` — mesmo contrato assumido do lado de `billing-service`, `POST /v1/billings/{id}/payment-events`\*).
2. Payment API chama o `Billing Service`, autenticado como Sistema Consumidor M2M.
3. `Billing Service` aplica sua própria transição de status na Cobrança correspondente (fora do escopo deste serviço — `billing-service`, ES-06 daquele serviço).
4. Payment API registra o resultado da chamada (sucesso/falha) em log/auditoria.

**Policies:** falha nesta chamada não reverte o Payment, já `APPROVED`/`REJECTED`/`REFUNDED` de forma definitiva neste serviço — sem retry automático nesta versão (mesmo padrão de `billing-service`/ADR-010).

**Regras:** BD-01, BD-14.

**Alternativas:**

* `Billing Service` indisponível/erro → Payment permanece no status já aplicado; falha registrada, sem reprocessamento automático nesta versão.

---

## ES-08 — Registro de Histórico

**Objetivo:** garantir rastreabilidade completa de toda mudança de status.

**Atores:** Payment Service (interno).

**Fluxo Principal:**

1. Qualquer comando que altere o `status` de um Payment (ES-01, ES-06) grava uma linha em `payment_status_history`, na mesma transação.
2. `fromStatus`, `toStatus`, `reason`, `providerEventId` (quando aplicável), `createdAt` são preenchidos.

**Regras:** BD-06 — histórico append-only, nunca alterado/removido; nenhuma atualização de Payment sem histórico correspondente na mesma transação.

---

## ES-09 — Auditoria de Operações

**Objetivo:** registrar toda operação financeira relevante, sem duplicar dado sensível.

**Atores:** Payment Service (interno, disparado por qualquer comando de escrita relevante).

**Fluxo Principal:**

1. Toda operação de ES-01, ES-06 bem-sucedida gera um registro de auditoria: `paymentId`, `billingId`, `operation`, `application`, `actor`, `createdAt`.

**Regras:** BD-18 — nunca grava chave Pix, conta bancária, CVV ou qualquer dado financeiro sensível.
