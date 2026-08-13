# Serviços de Domínio — Payment Service

> Um **Serviço de Domínio** encapsula uma regra do domínio que não pertence naturalmente a uma entidade/agregado específico — stateless, reaproveitado por múltiplos casos de uso. Este documento formaliza os quatro serviços de domínio hoje implícitos nas decisões de negócio (`03-business-decisions.md`) e no agregado (`08-aggregates.md`) — mesmo racional de `billing-service`/`person-service`/`storage-service`.

---

## Serviço de Idempotência

### Por que é um Serviço de Domínio

A regra "não criar dois Payments para a mesma operação" (BD-09) é avaliada uma única vez, no início do fluxo de criação (ES-01), antes de qualquer outra validação de negócio — isolá-la evita que a lógica de deduplicação fique misturada com a lógica de criação em si. A mesma necessidade existe, de forma análoga, para webhooks (BD-10) — mas com uma chave diferente (`providerEventId`) e um escopo diferente (por `provider`).

### Operações

| Operação | Assinatura conceitual | Regra aplicada |
|---|---|---|
| Verificar Chave de Criação Existente | `VerificarChave(idempotencyKey, application) → payment existente \| nenhum` | Consulta `payments` por `(idempotency_key, application)` — unicidade no contexto da Aplicação, não global (BD-09) |
| Verificar Evento de Webhook Existente | `VerificarEvento(provider, providerEventId) → evento existente \| nenhum` | Consulta `payment_provider_events` por `(provider, provider_event_id)` (BD-10) |

### Regras de negócio encapsuladas

1. A verificação de criação é sempre a primeira etapa do fluxo (ES-01), antes de qualquer validação de payload.
2. A verificação de webhook é sempre a primeira etapa do fluxo de recebimento (ES-05), antes de aplicar qualquer transição.
3. A unicidade de criação é sempre por par `(idempotencyKey, application)`; a de webhook, por par `(provider, providerEventId)` — nunca a mesma chave usada para as duas finalidades.

### Quem usa

* **Criação de Payment** (BC-01, ES-01) — chamado antes de qualquer outra validação.
* **Recebimento de Webhook** (BC-01, ES-05) — chamado antes de aplicar qualquer transição.

### O que este serviço não faz

* **Não decide o TTL/expiração de uma chave** — não especificado pelo documento funcional; nesta versão a unicidade é permanente (sem expiração), assumido\* (ver `12-acceptance-criteria.md`), mesmo comportamento já assumido por `billing-service`.

---

## Serviço de Transição de Status

### Por que é um Serviço de Domínio

A máquina de transição fechada (BD-07) é avaliada em dois pontos diferentes do sistema (criação, atualização por confirmação do provedor) — centralizar a validação evita que cada fluxo reimplemente a mesma tabela de transições permitidas de forma divergente.

### Operações

| Operação | Assinatura conceitual | Regra aplicada |
|---|---|---|
| Validar Transição | `ValidarTransicao(statusAtual, statusDestino) → permitida/rejeitada` | Consulta a tabela fechada de transições (BD-07, `09-domain-state-machines.md`) |
| Aplicar Transição | `AplicarTransicao(payment, statusDestino, reason, providerEventId) → payment atualizado` | Atualiza `status`, grava linha em `payment_status_history`, tudo na mesma transação |

### Regras de negócio encapsuladas

1. Nenhuma transição fora do catálogo fechado é aplicada, mesmo que solicitada por um webhook de provedor tecnicamente bem formado.
2. Toda transição aplicada grava histórico na mesma transação — nunca uma sem a outra.
3. `APPROVED`, `REJECTED` e `CANCELLED` nunca retornam a `PENDING`/`PROCESSING`; `REFUNDED` nunca retorna a `APPROVED`; `CANCELLED` nunca avança a `APPROVED` (transições explicitamente proibidas, seção 10 do documento funcional).

### Quem usa

* **Criação de Payment** (ES-01) — transição inicial (`null → PENDING`, e `PENDING → PROCESSING` se o envio síncrono ao provedor for bem-sucedido).
* **Atualização de Status por Confirmação do Provedor** (ES-06) — transição para `APPROVED`/`REJECTED`/`REFUNDED`/`PARTIALLY_REFUNDED`.

### O que este serviço não faz

* **Não decide o resultado da operação** — só aplica a transição já decidida por quem o chama (o provedor, via webhook); não interpreta o payload específico de cada provedor (isso é responsabilidade da abstração `PaymentProvider`, ver Serviço de Integração com Provedor, abaixo).

---

## Serviço de Integração com Provedor

### Por que é um Serviço de Domínio

A regra "nenhuma parte do domínio depende diretamente do contrato específico de um provedor" (BD-13) exige um ponto único de tradução entre o vocabulário interno (`Payment`, `type`, `method`) e o vocabulário externo de cada provedor.

### Operações

| Operação | Assinatura conceitual | Regra aplicada |
|---|---|---|
| Enviar Operação | `EnviarOperacao(payment) → { aceita, dadosParaPagador } \| rejeitada` | Traduz o `Payment` para o formato do provedor configurado (BD-13); usado na criação (ES-01) |
| Interpretar Webhook | `InterpretarWebhook(payload, provider) → { providerEventId, providerPaymentId, resultado }` | Traduz o payload específico do provedor para o vocabulário interno (ES-05) |
| Validar Autenticidade | `ValidarAutenticidade(request, provider) → válido/inválido` | Mecanismo específico do provedor (assinatura/segredo), Hotspot H02 |

### Regras de negócio encapsuladas

1. O restante da aplicação nunca lida com o formato bruto de request/response do provedor — só com o `Payment` já traduzido.
2. A escolha do provedor concreto é por configuração, nunca por lógica de negócio nesta versão (só um provedor implementado, Hotspot H01).

### Quem usa

* **Criação de Payment** (ES-01) — envio da operação.
* **Recebimento de Webhook** (ES-05) — interpretação e validação.

### O que este serviço não faz

* **Não decide o nome do provedor real a integrar** — decisão pendente do usuário (Hotspot H01).
* **Não implementa múltiplos provedores simultâneos** nesta versão — só a abstração está pronta para isso; a implementação concreta de um segundo provedor é evolução futura (seção 36 do documento funcional).

---

## Serviço de Obtenção de Dados do Recebedor

### Por que é um Serviço de Domínio

A regra "para `PAY`, obtenha o dado de destino do `Person Service`, nunca o duplique" (BD-16) é específica o suficiente para merecer isolamento — inclui a lógica de escolha da conta principal quando existir mais de uma.

### Operações

| Operação | Assinatura conceitual | Regra aplicada |
|---|---|---|
| Obter Conta de Recebimento | `ObterConta(personId) → conta principal \| nenhuma` | Chama `GET /v1/persons/{personId}/receiving-accounts`\*, seleciona a conta `isPrimary` (BD-16) |

### Regras de negócio encapsuladas

1. Só é chamado para Payments `type = PAY`.
2. Nunca persiste o dado retornado além do escopo da chamada ao provedor em curso.
3. Se não houver conta cadastrada, a criação do Payment falha antes de qualquer chamada ao provedor.

### Quem usa

* **Criação de Payment** (BC-01, ES-01/ES-04) — só quando `type = PAY`.

### O que este serviço não faz

* **Não valida a titularidade do documento** — essa validação já é feita pelo `Person Service` na criação da conta de recebimento (`person-service`, BD-08 daquele serviço); este serviço confia no dado já validado.
* **Não armazena nem cacheia o dado entre chamadas** — cada operação consulta novamente, garantindo que qualquer atualização de conta no `Person Service` seja refletida imediatamente.
