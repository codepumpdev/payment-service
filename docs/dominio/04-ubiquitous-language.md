# Glossário do Domínio — Payment Service

Termos ordenados alfabeticamente. Referências a BD-XX apontam para `03-business-decisions.md`; a ES-XX apontam para `02-event-stories.md`; a BC-XX apontam para `05-bounded-contexts.md`.

---

## Aplicação (Sistema Consumidor)

Aplicação corporativa que cria/consulta pagamentos via API REST deste serviço, autenticada por Token de Serviço M2M emitido por `auth-service` (BD-04). O escopo de unicidade de `idempotencyKey` é sempre por Aplicação (BD-09), nunca global. Tipicamente o `Billing Service` (para `PAY`) ou uma aplicação de checkout/painel (para `RECEIVE`).

---

## `auth-service`

Serviço Central de Autenticação e Autorização da empresa — origem de todo JWT/Token de Serviço consumido por este serviço (BD-04). `Payment Service` nunca implementa autenticação própria.

---

## `Billing Service`

Serviço que representa a obrigação financeira (BD-01) — fonte da verdade sobre *quanto* é devido, para quem, até quando. `Payment Service` sempre age a partir de uma cobrança já existente nele (`billingId`) e o informa de volta quando um pagamento é aprovado/rejeitado/estornado (ES-07).

---

## Correlation ID

Identificador (`X-Correlation-ID`) propagado entre `Payment Service`, `Billing Service`, `Payment Provider` e `Notification Service`, para rastrear uma operação financeira completa de ponta a ponta (BD-19).

---

## Idempotência de Webhook

Garantia de que um mesmo evento do provedor (`providerEventId`), reenviado mais de uma vez, nunca é processado duas vezes (BD-10). Distinta da idempotência de criação (ver `idempotencyKey`).

---

## `idempotencyKey`

Chave informada pelo Sistema Consumidor na criação de um Payment, usada para evitar duplicação em caso de reenvio da mesma requisição (BD-09). Única no contexto da Aplicação chamadora, não globalmente.

---

## Meio de Pagamento (`method`)

Mecanismo concreto usado para movimentar o valor — `PIX` (único implementado nesta versão), com o modelo preparado para `CREDIT_CARD`/`DEBIT_CARD`/`BANK_TRANSFER`/`BOLETO`/`OTHER` no futuro (BD-06).

---

## `Notification Service`

Serviço externo, já existente, responsável por decidir quais canais usar (e-mail/SMS/WhatsApp/push) para comunicar o resultado de um pagamento ao usuário final. `Payment Service` nunca envia notificação diretamente — sempre publica um evento (`PAYMENT_APPROVED`/`PAYMENT_REJECTED`/`PAYMENT_REFUNDED`) que aquele serviço consome.

---

## `Payment`

Agregado raiz deste serviço — representa uma operação financeira concreta, destinada a mover dinheiro em um dos dois sentidos (`RECEIVE`/`PAY`), sempre relacionada a uma cobrança do `Billing Service`. Ver `08-aggregates.md`.

---

## `paymentId`

Identificador único (`UUID`) de um Payment, gerado internamente na criação — nunca derivado do identificador do provedor (BD-03). É o identificador que os demais serviços da empresa devem persistir para referenciar um Payment.

---

## `Payment Provider`

Serviço externo responsável pela execução real da operação financeira (Pix, e futuramente outros meios) — abstraído pela interface `PaymentProvider` (BD-13), para que nenhuma regra de negócio dependa diretamente do contrato específico de um provedor. Nome real do primeiro provedor a integrar ainda não definido (Hotspot H01).

---

## `PaymentProvider` (abstração)

Interface interna (camada de infraestrutura) que isola o domínio do contrato específico de cada Payment Provider concreto — permite trocar de provedor, ou adicionar um segundo, sem alterar regra de negócio (BD-13).

---

## `Person Service`

Serviço externo, já existente, fonte oficial de dados cadastrais e de destino financeiro de uma Pessoa — CPF/CNPJ, chave Pix, conta bancária (`receiving_accounts`, já modelado por aquele serviço). `Payment Service` consulta esse dado para pagamentos `PAY`, sem jamais duplicá-lo (BD-16).

---

## `providerEventId`

Identificador único de um evento de webhook, atribuído pelo `Payment Provider` — usado para garantir idempotência de webhook (BD-10). Distinto de `providerPaymentId` (identifica o pagamento, não o evento).

---

## `providerPaymentId`

Identificador atribuído pelo `Payment Provider` a uma operação — mantido como referência auxiliar, nunca como identificador interno (BD-03). Usado para localizar um Payment a partir de um webhook (ES-05), mas nunca sozinho como garantia de autenticidade (a assinatura/segurança do webhook é validada separadamente, Hotspot H02).

---

## `PAY`

Um dos dois valores possíveis do campo `type` de um Payment — representa uma movimentação em que a **empresa paga** dinheiro a uma pessoa ou empresa. Corresponde, do lado do `Billing Service`, a uma cobrança `PAYABLE` (`billing-service`, BD-18). Ver também `RECEIVE`.

---

## Perfil

Identificador de autorização atribuído a uma Aplicação em `auth-service`, avaliado na entrada de `profiles` com `app: PAYMENT_SERVICE` do JWT (BD-04). Catálogo: `PAYMENT_READ`, `PAYMENT_CREATE`, `PAYMENT_CANCEL`, `PAYMENT_REFUND`.

---

## `RECEIVE`

Um dos dois valores possíveis do campo `type` de um Payment — representa uma movimentação em que a **empresa recebe** dinheiro de um cliente. Corresponde, do lado do `Billing Service`, a uma cobrança `RECEIVABLE` (`billing-service`, BD-18). Ver também `PAY`.

---

## Status

Campo (`PENDING`/`PROCESSING`/`APPROVED`/`REJECTED`/`CANCELLED`/`REFUNDED`/`PARTIALLY_REFUNDED`) que representa o estado corrente de um Payment, controlado por uma máquina de transição fechada (BD-07, `09-domain-state-machines.md`). `REFUNDED`/`PARTIALLY_REFUNDED` são alcançáveis nesta versão só de forma reativa, por webhook do provedor (BD-08).

---

## Tentativa

Cada `Payment` criado para a mesma cobrança representa uma tentativa independente de movimentação — uma tentativa recusada nunca é reaproveitada; uma nova tentativa sempre gera um novo Payment (BD-12).

---

## Token de Serviço (M2M)

JWT emitido por `auth-service` (`POST /oauth2/v1/token/service`) para chamadas de sistema-a-sistema — usado tanto por Sistemas Consumidores quanto por este serviço ao chamar `Billing Service`/`Person Service`. Ver BD-04 e `padrao-desenvolvimento.md`, seção 9.3.

---

## Webhook

Notificação assíncrona enviada pelo `Payment Provider` a este serviço (`POST /v1/payments/webhooks/{provider}`), informando o resultado de uma operação em processamento. Sujeito a validação de autenticidade (Hotspot H02) e a idempotência por `providerEventId` (BD-10).

---

## Operação em nome de usuário (dois tokens)

Uma operação **em nome de** um usuário sobre o `payment-service` (aplicação alvo) usa **dois tokens** na mesma requisição (`padrao-desenvolvimento.md` seção 9.4): `Authorization: Bearer <SERVICE_JWT>` (a **aplicação chamadora**, identidade autorizada) + `X-User: <USER_JWT>` (o **usuário**, contexto). O `USER JWT` é **específico de uma aplicação** (um único `profile`): o `plan` aplicável vem **direto** de `profile.plan` e `profile.app` diz a aplicação do contexto (confiável, assinado); não há header `X-User-App` nem o erro `403 CONTEXTO_APLICACAO_INVALIDO`. O `sub` do usuário vem do **`USER JWT`** (`X-User`) — base para aplicar limite/retenção. Distinta da operação **sistema-a-sistema** (só `SERVICE JWT`, sem `X-User`). No encadeamento, o `X-User` é fixo; só o `Authorization` muda por salto (seção 9.3/9.4/26.2).

---

## Recurso Externo (`PAYMENT`)

Capacidade **gated por plano** (seção 26.10 do padrão) — o `payment-service` é o exemplo da spec. `PAYMENT` é o recurso externo que representa **executar uma movimentação financeira**: `FREE → PAYMENT = não permitido`; `PRO`/`MAX → PAYMENT = permitido`, configurável. Ao receber uma operação de pagamento **em nome de um usuário** (`X-User` + `SERVICE JWT`, seção 9.4), o serviço **valida o recurso `PAYMENT` contra o plano — lido direto de `profile.plan` do único `profile` do `USER JWT` (`X-User`) — antes de qualquer efeito**; usuário `FREE` → `403 RECURSO_NAO_PERMITIDO_NO_PLANO`. É a **regra comercial central** deste serviço como aplicação alvo (ADR-022/BD-21).

---

## Plano / Titular / Retenção (ADR-022)

| Termo | Definição |
|---|---|
| **Plano** | Estado comercial do usuário (`FREE`/`PRO`/`MAX`, enum `Plan` da `codepump-lib`), lido **direto** de **`profile.plan`** do único `profile` do **`USER JWT`** (`X-User`; o token é específico de uma aplicação — `profile.app` diz o contexto; seção 9.3/26.2). `FREE` não permite o recurso `PAYMENT`, limita registros e aplica retenção; `PRO`/`MAX` permitem `PAYMENT` sem limite; `MAX` = `PRO` no MVP |
| **Titular** (`owner_user_id`) | Usuário dono do Payment — o **`sub` do `USER JWT`** (`X-User`), referência **opaca** ao `auth-service`. Base da contagem de limite e do escopo de retenção por usuário. **Não** é dado financeiro de destino (BD-16 preservada) |
| **Limite de registros** (`payment.maxRecords`) | Quantidade máxima de Payments por titular `FREE`; configurável (assumido `20`\*); excedente → `403 LIMITE_PLANO_ATINGIDO`. Secundário ao gating de recurso |
| **Período de Retenção** (`retentionDays`) | Dias de retenção temporária no plano `FREE`; configurável (assumido `30`\*) |
| **`purgeAt`** (`payments.purge_at`) | Data de expurgo da retenção `FREE` (`created_at + retentionDays`); só na entidade raiz `payments`; `NULL` quando não há retenção |
| **Expurgo** | Remoção física dos Payments com `purge_at <= now()` e seus relacionados, **dentro** do `POST /internal/purge` (segundo motivo, além do órfão-`PENDING` de ADR-021), disparado pelo `scheduler-service` |
