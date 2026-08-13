# Bounded Contexts — Payment Service

---

# BC-01 — Payment

## Responsabilidade

Criar, consultar e controlar o status de pagamentos — representando a movimentação financeira real (não a obrigação, BD-01). Núcleo do serviço e porta de entrada para o `paymentId` (ES-01 a ES-07).

## Agregado Principal

Payment

## Entidades

* Payment *(`id`, `type`, `billingId`, `amount`, `currency`, `method`, `status`, `provider`, `providerPaymentId`, `idempotencyKey`, `application`, `createdAt`, `updatedAt` — BD-02, BD-03, BD-05, BD-06, BD-07, BD-09)*
* Histórico de Status *(`id`, `paymentId`, `fromStatus`, `toStatus`, `reason`, `providerEventId`, `createdAt` — ver `08-aggregates.md`)*
* Evento de Provedor *(`id`, `provider`, `providerEventId`, `paymentId`, `eventType`, `receivedAt`, `processedAt`, `status` — BD-10)*

## Value Objects

* Valor Monetário (`amount`/`currency`, precisão decimal — BD-05)
* Tipo do Payment (`type` ∈ {`RECEIVE`, `PAY`}, imutável — BD-02)

## Comandos

* Criar Payment *(ES-01)*
* Consultar Payment por Identificador *(ES-02)*
* Consultar Payments por Cobrança *(ES-03)*
* Obter Dados do Recebedor *(interno, só `PAY` — ES-04)*
* Receber Webhook do Provedor *(ES-05)*
* Aplicar Resultado do Provedor *(interno, ES-06)*
* Informar Billing Service *(interno, ES-07)*

## Eventos

* Payment Criado
* Payment em Processamento
* Payment Aprovado
* Payment Rejeitado
* Payment Cancelado
* Payment Estornado
* Payment Parcialmente Estornado\* *(assumido, ver Hotspot H03)*

## Consome

* Webhook do `Payment Provider` *(externo, via HTTP síncrono inbound — BD-10, BD-14)*.
* `GET /v1/persons/{personId}/receiving-accounts`\* do `Person Service` *(consulta síncrona, só `PAY` — BD-16)*.
* `GET /v1/billings/{id}`\* do `Billing Service` *(consulta síncrona, valor disponível — BD-11)*.

## Publica

* Payment Criado, Payment em Processamento, Payment Aprovado, Payment Rejeitado, Payment Cancelado, Payment Estornado, Payment Parcialmente Estornado *(consumidos internamente por BC-02 — Auditoria; também disparam chamada HTTP outbound para `Billing Service`/`Notification Service`, fora do modelo de eventos de domínio — BD-14, BD-18)*.

---

# BC-02 — Auditoria

## Responsabilidade

Registrar toda operação financeira relevante do BC-01, sem duplicar dado sensível (BD-18).

## Agregado Principal

nenhum — BC de leitura/registro, sem regra de negócio própria além de "registrar o que aconteceu" (mesmo padrão de BC-02 de `billing-service`).

## Entidades

* Registro de Auditoria *(`id`, `paymentId`, `billingId`, `operation`, `application`, `actor`, `createdAt` — BD-18)*

## Value Objects

nenhum específico.

## Comandos

* Registrar Auditoria *(interno, disparado por qualquer comando de escrita de BC-01 — ES-09)*

## Eventos

* Operação Auditada

## Consome

* Payment Criado, Payment Aprovado, Payment Rejeitado, Payment Cancelado, Payment Estornado, Payment Parcialmente Estornado *(de BC-01)*

## Publica

* nenhum — BC terminal, ponto final da cadeia de eventos internos deste serviço.
