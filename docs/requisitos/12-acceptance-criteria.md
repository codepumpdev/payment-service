# Requisitos — Critérios de Aceite

> Detalha, em formato Gherkin (Dado/Quando/Então), os critérios de aceite mínimos já registrados em `10-functional-requirements.md` (RF-01 a RF-09) — mesma numeração. Não substitui aquele documento; adiciona os cenários concretos que faltavam para abrir `Planejamento/Histórias` (etapa 8). Mesmo formato de `billing-service`/`person-service`/`storage-service`.
>
> Onde a documentação registra um comportamento **em aberto** (Hotspots H01, H02, H03 — `../dominio/01-event-storming-big-picture.md`), os cenários abaixo descrevem o comportamento provisório/atual, sem inventar uma resolução definitiva.

---

## Convenções

* Formato: `Cenário` / `Dado` / `Quando` / `Então` / `E` — Gherkin em português.
* **\*** ao lado de um valor = assumido em `17-api-contracts.md`/`11-non-functional-requirements.md`, não fixado por uma Decisão de Negócio — ver "Valores Assumidos".
* Cenários cobrem o mínimo para exercitar cada critério de aceite de `10-functional-requirements.md` — não é suíte de testes exaustiva.

---

## Valores Assumidos (não fixados por uma Decisão de Negócio)

| Parâmetro | Valor assumido | Por quê essa escolha | Origem |
|---|---|---|---|
| Nome do primeiro provedor a integrar | **`PROVIDER_A`\*** | Documento funcional usa como exemplo ilustrativo (seções 6, 17); nenhum provedor real foi nomeado (Hotspot H01) | `dominio/01-event-storming-big-picture.md` (H01) |
| Contrato de consulta de valor disponível da cobrança (RF-01) | **`GET /v1/billings/{id}`, campo `remainingAmount`\*** | Não especificado por este documento funcional (seção 12); reaproveita o contrato já publicado por `billing-service` | `dominio/03-business-decisions.md` (BD-11) |
| Contrato de consulta de dados de recebimento (RF-04) | **`GET /v1/persons/{personId}/receiving-accounts`, Perfil `RECEIVING_READ`\*** | Não especificado por este documento funcional (seção 15); reaproveita o contrato já publicado por `person-service` | `dominio/03-business-decisions.md` (BD-16) |
| Contrato de informe ao Billing Service (RF-07) | **`POST /v1/billings/{id}/payment-events`, payload `{ event, amount, paidAt }`\*** | Não especificado por este documento funcional (seção 26); reaproveita o contrato já assumido do lado de `billing-service` | `dominio/06-context-map.md` |
| Mecanismo de autenticidade do webhook (RF-05) | **assinatura HMAC com segredo no OpenBao\*** | Não especificado (Hotspot H02) — depende do provedor escolhido (H01) | `dominio/01-event-storming-big-picture.md` (H02) |
| Endpoint de cancelamento (transição `PENDING → CANCELLED`) | **`POST /v1/payments/{id}/cancel`\*** | Não citado literalmente pelo documento funcional, mas inferido pela combinação de Perfil `PAYMENT_CANCEL` + evento `PAYMENT_CANCELLED` + transição do diagrama (seção 10) | `dominio/09-domain-state-machines.md` |
| Código de erro para recebedor sem conta cadastrada (RF-04) | **`422 RECEBEDOR_SEM_CONTA`\*** | Não especificado pelo documento funcional | `dominio/02-event-stories.md` (ES-04) |
| Escopo de unicidade de `idempotencyKey` (RF-01) | **por par `(idempotencyKey, application)`\*** | Documento funcional não repete "por aplicação" explicitamente (diferente de `billing-service`); assumido pela mesma convenção organizacional | `dominio/03-business-decisions.md` (BD-09) |
| Tamanho de página — padrão/máximo (consultas) | **`size=20` padrão, `size=100` máximo** | Convenção de mercado, mesmo valor já usado nos demais serviços | `17-api-contracts.md`, Convenções |
| Formato de data/hora nas respostas | **ISO 8601 com timezone** | Convenção de mercado | `17-api-contracts.md`, Convenções |
| TTL/expiração de `idempotencyKey` | **sem expiração\*** | Não especificado pelo documento funcional; unicidade tratada como permanente nesta versão | `dominio/07-domain-services.md` (Serviço de Idempotência) |

Revisar junto de `11-non-functional-requirements.md` (RNF-10) assim que houver medição real ou decisão explícita do usuário.

---

## RF-01 — Criação de Payment

```gherkin
Cenário: Payment RECEIVE criado com sucesso
  Dado um Sistema Consumidor autenticado com o Perfil PAYMENT_CREATE
  Quando ele chama POST /v1/payments com type "RECEIVE", billingId de uma cobrança RECEIVABLE existente, amount 150.90, currency "BRL", method "PIX" e idempotencyKey "ORDER-123456-PAYMENT"
  Então o sistema responde 201 Created com o paymentId gerado
  E status é PENDING, ou PROCESSING se o envio ao provedor for aceito na mesma operação

Cenário: Payment PAY criado com sucesso
  Dado um Sistema Consumidor autenticado com o Perfil PAYMENT_CREATE
  Quando ele chama POST /v1/payments com type "PAY", billingId de uma cobrança PAYABLE existente, amount 500.00, currency "BRL", method "PIX" e idempotencyKey "ORDER-123456-PAYOUT"
  Então o Payment Service consulta o Person Service para obter os dados de recebimento antes de enviar ao provedor
  E o sistema responde 201 Created

Cenário: Reenvio da mesma idempotencyKey não cria duplicata
  Dado um Payment já criado com idempotencyKey "ORDER-123456-PAYMENT" pela aplicação "order-service"
  Quando a mesma aplicação chama POST /v1/payments novamente com a mesma idempotencyKey
  Então o sistema responde 200 OK com o Payment já existente
  E nenhum novo Payment é criado

Cenário: billingId inexistente
  Dado um payload com billingId que não existe no Billing Service
  Quando o Payment é criado
  Então o sistema responde 404 COBRANCA_NAO_ENCONTRADA

Cenário: amount ultrapassa o valor disponível da cobrança
  Dado uma cobrança com remainingAmount 100.00
  Quando o Sistema Consumidor chama POST /v1/payments com amount 150.00 para essa cobrança
  Então o sistema responde 409 VALOR_EXCEDE_COBRANCA

Cenário: method não implementado
  Dado um payload com method "BOLETO"
  Quando o Payment é criado
  Então o sistema responde 400 METODO_NAO_SUPORTADO

Cenário: Token ausente ou Perfil insuficiente
  Dado uma chamada POST /v1/payments sem JWT válido, ou com um JWT sem o Perfil PAYMENT_CREATE
  Quando a chamada é processada
  Então o sistema responde 401 NAO_AUTENTICADO ou 403 PERFIL_INSUFICIENTE
  E nenhum registro é criado
```

---

## RF-02 — Consulta de Payment por Identificador

```gherkin
Cenário: Consulta de payment existente
  Dado um Payment já criado
  Quando o Sistema Consumidor chama GET /v1/payments/{id}
  Então o sistema responde 200 OK com todos os campos do Payment

Cenário: Payment inexistente
  Dado um id que não existe
  Quando o Sistema Consumidor chama GET /v1/payments/{id}
  Então o sistema responde 404 PAYMENT_NAO_ENCONTRADO
```

---

## RF-03 — Consulta de Payments por Cobrança

```gherkin
Cenário: Consulta paginada por cobrança
  Dado uma cobrança com 3 Payments cadastrados (2 REJECTED, 1 APPROVED)
  Quando o Sistema Consumidor chama GET /v1/payments?billingId={billingId}
  Então o sistema responde 200 OK com os 3 Payments em content e totalElements 3

Cenário: Nenhum Payment para a cobrança informada
  Dado nenhuma cobrança com Payments relacionados
  Quando a consulta é feita
  Então o sistema responde 200 OK com lista vazia
```

---

## RF-04 — Obtenção de Dados do Recebedor (`PAY`)

```gherkin
Cenário: Dados do recebedor obtidos com sucesso
  Dado uma Pessoa com uma conta de recebimento PIX marcada como principal
  Quando um Payment PAY é criado para essa Pessoa
  Então o Payment Service consulta GET /v1/persons/{personId}/receiving-accounts
  E usa a conta marcada como isPrimary para enviar a operação ao provedor

Cenário: Recebedor sem conta cadastrada
  Dado uma Pessoa sem nenhuma conta de recebimento cadastrada
  Quando um Payment PAY é criado para essa Pessoa
  Então o sistema responde 422 RECEBEDOR_SEM_CONTA
  E nenhuma chamada ao provedor é feita
```

---

## RF-05 — Recebimento de Webhook do Provedor

```gherkin
Cenário: Webhook processado com sucesso
  Dado um Payment PROCESSING com providerPaymentId "PIX-123456"
  Quando o Payment Provider chama POST /v1/payments/webhooks/PROVIDER_A com um evento de aprovação válido e providerEventId "PROVIDER_EVENT_123456"
  Então o sistema responde 200 OK
  E dispara RF-06 para aplicar a transição

Cenário: Webhook duplicado não é reprocessado
  Dado um evento com providerEventId "PROVIDER_EVENT_123456" já processado
  Quando o Payment Provider reenvia o mesmo webhook
  Então o sistema responde 200 OK
  E nenhuma nova transição é aplicada

Cenário: Assinatura inválida
  Dado um webhook sem assinatura válida
  Quando o Payment Provider chama o endpoint de webhook
  Então o sistema responde 401 WEBHOOK_INVALIDO
  E nenhuma transição é aplicada
```

---

## RF-06 — Atualização de Status por Confirmação do Provedor

```gherkin
Cenário: Payment aprovado
  Dado um Payment PROCESSING
  Quando o webhook confirma aprovação
  Então o status do Payment passa a APPROVED
  E RF-07 é disparado para informar o Billing Service

Cenário: Payment rejeitado
  Dado um Payment PROCESSING
  Quando o webhook confirma rejeição
  Então o status do Payment passa a REJECTED
  E RF-07 é disparado

Cenário: Transição não permitida rejeitada
  Dado um Payment já APPROVED
  Quando um webhook tenta aplicar REJECTED
  Então a transição é rejeitada, registrada como anomalia
  E o status do Payment permanece APPROVED

Cenário: Estorno reportado pelo provedor (Hotspot H03)
  Dado um Payment APPROVED
  Quando o Payment Provider envia um webhook reportando estorno total
  Então o status do Payment passa a REFUNDED
  E RF-07 é disparado
  E nenhum endpoint deste serviço iniciou esse estorno — foi inteiramente reativo
```

---

## RF-07 — Informar Billing Service do Resultado

```gherkin
Cenário: Billing Service informado com sucesso
  Dado um Payment recém aprovado
  Quando o Payment Service chama POST /v1/billings/{id}/payment-events
  Então o Billing Service responde 200 OK
  E o resultado da chamada é registrado em log/auditoria

Cenário: Falha ao informar o Billing Service não reverte o Payment
  Dado um Payment recém aprovado
  Quando a chamada ao Billing Service falha
  Então o Payment permanece APPROVED
  E nenhum retry automático é disparado nesta versão
```

---

## RF-08 — Registro de Histórico de Status

```gherkin
Cenário: Toda transição gera histórico
  Dado um Payment PROCESSING
  Quando ele transiciona para APPROVED via confirmação do provedor
  Então um registro em payment_status_history é criado com fromStatus PROCESSING e toStatus APPROVED
  E o registro nunca pode ser alterado ou removido posteriormente
```

---

## RF-09 — Auditoria de Operações

```gherkin
Cenário: Criação de payment gera registro de auditoria
  Dado um Sistema Consumidor autenticado
  Quando um Payment é criado com sucesso
  Então um registro de auditoria é criado com operation "PAYMENT_CREATED", o paymentId, a application e o actor do chamador
  E nenhum dado financeiro sensível aparece no registro
```

---

## Rastreabilidade

| RF | Fluxo | ES | BD/ADR principais |
|---|---|---|---|
| RF-01 | 1 | ES-01 | BD-02, BD-05, BD-06, BD-09, BD-11 |
| RF-02 | 2 | ES-02 | BD-03, BD-04 |
| RF-03 | 3 | ES-03 | BD-12 |
| RF-04 | 4 | ES-04 | BD-16 |
| RF-05 | 5 | ES-05 | BD-10 |
| RF-06 | 6 | ES-06 | BD-07, BD-08 |
| RF-07 | 7 | ES-07 | BD-01, BD-14 |
| RF-08 | 8 | ES-08 | — |
| RF-09 | 9 | ES-09 | BD-15, BD-18 |

---

## Pontos Abertos

* **Hotspot H01** — provedor real a integrar: cenários acima usam `PROVIDER_A` como placeholder; revisar quando o usuário definir o provedor efetivo.
* **Hotspot H02** — mecanismo exato de autenticidade do webhook: cenário de RF-05 assume validação de assinatura, sem especificar o algoritmo/header; revisar junto de H01.
* **Hotspot H03** — estorno iniciado pelo próprio serviço: cenário de RF-06 reflete o comportamento provisório (só reativo, via webhook); revisar quando o usuário confirmar o escopo de `POST /payments/{id}/refund`.

---

## Evolução

Revisar todos os cenários marcados com Hotspot assim que a respectiva decisão do usuário for registrada — seguindo o mesmo padrão de riscado + nota datada já aplicado em `billing-service`/`person-service`/`storage-service`.
