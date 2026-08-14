# Event Storming — Big Picture — Payment Service

> Escopo: `Payment Service`, serviço central de processamento de pagamentos — movimenta dinheiro nos dois sentidos (`RECEIVE`/`PAY`), a partir de uma obrigação já registrada pelo `Billing Service`. Mesmo formato de `billing-service`/`person-service`/`storage-service`.

---

# Atores

* **Sistema Consumidor** — aplicação corporativa que cria/consulta pagamentos via API, autenticada por Token de Serviço M2M (BD-04). Tipicamente o `Billing Service` (para `PAY`) ou uma aplicação de checkout/painel (para `RECEIVE`).
* **Billing Service** — informa a obrigação financeira relacionada (`billingId`); é informado de volta quando o pagamento é aprovado/rejeitado/cancelado/estornado. Relação bidirecional, mesma relação já documentada do lado de `billing-service` (BD-01, BD-18, BD-19 daquele serviço).
* **Payment Provider** — serviço externo (nome real ainda não definido, Hotspot H01) que efetivamente processa a operação financeira (Pix, e futuramente outros meios) e confirma o resultado via webhook.
* **Person Service** — fonte oficial de dados de destino (CPF/CNPJ, chave Pix, conta bancária) para pagamentos `PAY` — já expõe `GET /v1/persons/{id}/receiving-accounts` (Perfil `RECEIVING_READ`), reaproveitado por este serviço (BD-16).
* **Notification Service** — recebe eventos publicados por este serviço (`PAYMENT_APPROVED`/`PAYMENT_REJECTED`/`PAYMENT_REFUNDED`) e decide como comunicar o resultado ao usuário final — este serviço nunca envia notificação diretamente (BD-01, seção 27 do documento funcional).
* **Job/Rotina Interna** — não existe rotina periódica própria neste serviço nesta versão (diferente de `billing-service`); toda transição de status é reativa — disparada por uma chamada HTTP (criação, webhook).

---

# Fluxos

## 1. Criação de Payment (`RECEIVE` ou `PAY`)

* **Ator:** Sistema Consumidor.
* **Comando:** Criar Payment (`POST /v1/payments`).
* **Evento:** **Payment Criado** (`PAYMENT_CREATED`) e, se o envio síncrono ao provedor for bem-sucedido, **Payment em Processamento** (`PAYMENT_PROCESSING`).
* **Regra:** exige `type` (`RECEIVE`/`PAY`, imutável após criação — BD-02), `billingId`, `amount`, `currency`, `method`, `idempotencyKey` (BD-09); valida que a Cobrança (`billingId`) existe e que `amount` não ultrapassa o valor disponível da cobrança — consulta síncrona ao `Billing Service` (assumido\* como `GET /v1/billings/{id}`, campo `remainingAmount`, já documentado por aquele serviço — BD-11); verifica `idempotencyKey` antes de qualquer outra validação (BD-09); cria o Payment com `status = PENDING`; tenta, na mesma operação, enviar a operação ao provedor (BD-13) — se aceito, transiciona para `PROCESSING` e retorna os dados necessários para o pagador concluir a operação (ex.: QR Code/copia-e-cola Pix, formato exato dependente do provedor, Hotspot H01); se a chamada ao provedor falhar, o Payment permanece `PENDING`, sem retry automático nesta versão (mesmo padrão de ausência de fila já registrado por `billing-service`, BD-14/ADR-010).

## 2. Consulta de Payment por Identificador

* **Ator:** Sistema Consumidor.
* **Comando:** Consultar Payment (`GET /v1/payments/{id}`).
* **Evento:** nenhum — leitura direta.
* **Regra:** retorna todos os campos do Payment, exceto dado interno de auditoria; `404` se `id` inexistente.

## 3. Consulta de Payments por Cobrança

* **Ator:** Sistema Consumidor (tipicamente `Billing Service`).
* **Comando:** Consultar Payments por Billing (`GET /v1/payments?billingId={billingId}`).
* **Evento:** nenhum — leitura direta.
* **Regra:** retorna todos os Payments relacionados à cobrança, paginado — necessário para tentativas múltiplas, pagamento parcial, ou consulta de estorno (seção 21 do documento funcional); nunca `404`, lista vazia quando não houver Payment relacionado.

## 4. Obtenção de Dados do Recebedor (`PAY`)

* **Ator:** Payment Service (interno, disparado pelo Fluxo 1 quando `type = PAY`, antes do envio ao provedor).
* **Comando:** Consultar Conta de Recebimento (`Payment Service` → `Person Service`, `GET /v1/persons/{personId}/receiving-accounts`\*, assumido — Perfil `RECEIVING_READ`, BD-16).
* **Evento:** **Dados do Recebedor Obtidos** ou **Recebedor Sem Conta Cadastrada**.
* **Regra:** usa a conta marcada como principal (`isPrimary`, já modelada por `person-service`, BD-04 daquele serviço) quando existir mais de uma; nunca armazena o dado retornado além do escopo da operação em curso (BD-16); se a Pessoa não tiver nenhuma conta de recebimento cadastrada, a criação do Payment `PAY` falha (`422`\*, código a definir — ver `12-acceptance-criteria.md`, Valores Assumidos) antes de qualquer chamada ao provedor.

## 5. Recebimento de Webhook do Provedor

* **Ator:** Payment Provider (externo, chamada HTTP síncrona inbound, sem autenticação M2M via `auth-service` — mecanismo de segurança próprio do provedor, Hotspot H02).
* **Comando:** Receber Webhook (`POST /v1/payments/webhooks/{provider}`).
* **Evento:** **Webhook Recebido**.
* **Regra:** localiza o Payment pelo `providerPaymentId`, nunca confia só nesse identificador — valida a autenticidade da requisição (assinatura/segredo do provedor, Hotspot H02) antes de processar; extrai `providerEventId` e verifica se já foi processado (BD-10) — se já processado, retorna sucesso sem reexecutar (idempotência de webhook); se novo, encaminha ao Fluxo 6.

## 6. Atualização de Status por Confirmação do Provedor

* **Ator:** Payment Service (interno, disparado pelo Fluxo 5 após validação).
* **Comando:** Aplicar Resultado do Provedor.
* **Evento:** **Payment Aprovado** (`PAYMENT_APPROVED`), **Payment Rejeitado** (`PAYMENT_REJECTED`), **Payment Estornado** (`PAYMENT_REFUNDED`) ou **Payment Parcialmente Estornado** (`PAYMENT_PARTIALLY_REFUNDED`\* — não citado no catálogo de eventos da seção 25 do documento funcional, mas simétrico ao catálogo de status da seção 9; assumido\* por consistência, ver Hotspot H03).
* **Regra:** valida que a transição é permitida pela máquina de estados fechada (BD-07, `09-domain-state-machines.md`) antes de aplicar; registra histórico (Fluxo 8) na mesma transação; um Payment `APPROVED`/`REJECTED`/`CANCELLED` nunca é revertido para `PENDING`/`PROCESSING` (transições proibidas explícitas, seção 10 do documento funcional); `REFUNDED`/`PARTIALLY_REFUNDED` só são alcançados nesta versão via este fluxo reativo (o próprio provedor reportando um estorno por webhook) — nenhum endpoint deste serviço inicia um estorno nesta versão (BD-08, Hotspot H03).

## 7. Informar Billing Service do Resultado

* **Ator:** Payment Service (interno, disparado ao final do Fluxo 6, quando o resultado for `APPROVED`/`REJECTED`/`REFUNDED`/`PARTIALLY_REFUNDED`).
* **Comando:** Informar Resultado (`Payment Service` → `Billing Service`, HTTP síncrono outbound, assumido\* como `POST /v1/billings/{id}/payment-events` — contrato já assumido do lado de `billing-service`, BD-13/Hotspot H03 daquele serviço; esta documentação confirma esse mesmo endpoint como o alvo da chamada).
* **Evento:** **Billing Service Informado** ou **Falha ao Informar Billing Service**.
* **Regra:** aplicável a `RECEIVE` e `PAY` igualmente — o `Billing Service` já trata os dois sentidos de forma simétrica (`billing-service`, BD-18); se a chamada falhar, o Payment já está `APPROVED`/`REJECTED` de forma definitiva neste serviço — a falha de notificação não reverte o Payment, fica sujeita a reprocessamento fora do escopo desta versão (mesmo padrão de ausência de retry automático já registrado por `billing-service`).

## 8. Registro de Histórico

* **Ator:** Payment Service (interno).
* **Comando:** nenhum — efeito colateral de qualquer comando que altere `status` (Fluxos 1, 6).
* **Evento:** nenhum — o histórico em si não gera evento de domínio adicional.
* **Regra:** toda transição de `status` grava uma linha em `payment_status_history`, na mesma transação (BD-06); histórico append-only, nunca alterado/removido.

## 9. Auditoria de Operações

* **Ator:** Payment Service (interno, disparado por qualquer comando de escrita relevante).
* **Comando:** nenhum — efeito colateral automático.
* **Evento:** **Operação Auditada**.
* **Regra:** toda operação de Fluxos 1, 6 gera um registro de auditoria (`paymentId`, `billingId`, `operation`, `application`, `actor`, `createdAt` — BD-18); nunca grava dado financeiro sensível (chave Pix, conta bancária, CVV) no registro de auditoria.

---

# Hotspots

* **H01 — Provedor real a integrar na primeira versão.** O documento funcional usa `PaymentProvider` como abstração e cita "Provider A"/"Provider B"/"Provider C" apenas como exemplos ilustrativos (seção 17); o JSON de exemplo da seção 6 usa `"provider": "PROVIDER_A"`, também um placeholder. Nenhum provedor real de Pix (instituição, adquirente, PSP) foi nomeado. Esta documentação assume `PROVIDER_A` como o nome interno do primeiro provedor a integrar, sem vincular a nenhuma instituição real — decisão pendente do usuário: qual provedor efetivamente contratar/integrar.
* **H02 — Mecanismo exato de autenticidade do webhook.** O documento funcional diz apenas "valide a assinatura ou mecanismo de segurança fornecido pelo provedor" (seção 18) — sem especificar algoritmo, header ou segredo, porque depende diretamente do provedor escolhido (H01). Esta documentação assume um mecanismo de assinatura HMAC com segredo armazenado no OpenBao (`arquitetura/15-infrastructure.md`), a ser confirmado/ajustado quando H01 for resolvido.
* **H03 — Estorno: iniciado só pelo provedor (reativo) nesta versão, sem endpoint próprio.** A seção 24 do documento funcional abre com "Implemente posteriormente o estorno" e a lista explícita de "Primeira Versão" (seção 35) não inclui `POST /payments/{id}/refund`; ao mesmo tempo, a seção 9 já inclui `REFUNDED`/`PARTIALLY_REFUNDED` no catálogo fechado de status "a utilizar inicialmente", e a seção 25 já inclui `PAYMENT_REFUNDED` no catálogo de eventos iniciais. Esta documentação reconcilia as duas leituras assumindo que os dois status são alcançáveis nesta versão **somente de forma reativa** — se o próprio `Payment Provider` reportar um estorno via webhook (Fluxo 5/6), fora do controle deste serviço —, mas que nenhum endpoint deste serviço **inicia** ativamente um estorno até uma versão futura (`POST /payments/{id}/refund` fica fora do escopo da primeira versão, BD-08). Decisão pendente do usuário: confirmar essa leitura, ou esclarecer se o estorno reativo também deveria ficar fora da primeira versão. *(Nota de 2026-08-13, verificação: essa mesma ambiguidade se propaga ao contrato outbound com `billing-service` — o `POST /v1/billings/{id}/payment-events` daquele serviço hoje só aceita `event ∈ {PAYMENT_APPROVED, PAYMENT_REJECTED, PAYMENT_REFUNDED}`, sem `PAYMENT_PARTIALLY_REFUNDED`; resolver H03 aqui também deve esclarecer se `billing-service` precisa ampliar aquele catálogo — ver `contratos/18-event-contracts.md`.)*
* **H04 — `Billing Service` (e, com restrição ainda maior, `Person Service`) são dependências obrigatórias do `GET /ready` deste serviço?** *(Novo, 2026-08-13, junto da adoção do padrão organizacional de Health Check/Readiness Check — `padrao-desenvolvimento.md` seção 12, ADR-019.)* A consulta síncrona ao `Billing Service` na criação de Payment (`GET /v1/billings/{id}`, BD-11) é genuinamente **bloqueante** — sem ela, nenhum Payment pode ser criado —, mas restrita ao único endpoint de criação (`POST /v1/payments`); a consulta ao `Person Service` (BD-16) é bloqueante com restrição ainda maior — só dentro da criação, e só para `type = PAY`. A regra organizacional (seção 12.3 de `padrao-desenvolvimento.md`) não distingue explicitamente "dependência bloqueante para todo o serviço" de "dependência bloqueante só para um subconjunto de endpoints" — mesma lacuna já identificada por `person-service` (Hotspot H05 daquele serviço, para `storage-service`). ADR-019 decide, por ora, **não** incluir nenhuma das duas no `/ready`, reaproveitando o mesmo raciocínio de `person-service`, mas fica registrado aqui como Hotspot para eventual alinhamento organizacional e para revisão caso o padrão de uso se amplie. Não bloqueia a Implementação (etapa 9).

---

# Consultas Administrativas

Consulta de histórico de status (`GET /v1/payments/{id}/history`\*, análoga à de `billing-service`) e consulta de eventos de provedor recebidos (`payment_provider_events`) não correspondem a nenhum dos 9 fluxos numerados acima (operações de leitura administrativa, não fluxos de negócio com regra própria) — contratadas diretamente em `contratos/17-api-contracts.md`.
