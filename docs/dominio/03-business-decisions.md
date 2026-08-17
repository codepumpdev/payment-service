# Decisões de Negócio — Payment Service

> Numeradas sequencialmente (`BD-01`, `BD-02`, ...), nunca renumeradas/reutilizadas. Correções consolidam a decisão para o estado vigente, sem riscados nem notas datadas — a rastreabilidade histórica fica no `roadmap.md` (`padrao-desenvolvimento.md`, seção 1). Mesmo formato de `billing-service`/`person-service`/`storage-service`.

---

## BD-01 — Separação entre Movimentação (Payment Service) e Obrigação (Billing Service)

**Origem:** Documento funcional, seções 1, 2, 4, 26, 39.

**Contexto:** um único serviço que decidisse *quanto* é devido e *como* efetivamente mover o dinheiro acumularia responsabilidades com ciclos de evolução muito diferentes (regra de cobrança muda por decisão de negócio; processamento de pagamento muda por integração com provedor/banco/adquirente) — mesmo racional que já levou à criação separada do `Billing Service`.

**Decisão:** `Payment Service` representa exclusivamente a **movimentação financeira** — nunca cria pedido, nunca cria cobrança, nunca controla vencimento, nunca controla contas a receber/a pagar. A obrigação financeira (quanto se deve, para quem, até quando) é e continua sendo responsabilidade exclusiva do `Billing Service`. `Payment Service` só age a partir de uma cobrança já existente (`billingId`), tanto para `RECEIVE` (o `Billing Service` tem uma `RECEIVABLE`) quanto para `PAY` (o `Billing Service` tem uma `PAYABLE`).

**Impacto:** define o limite de responsabilidade de todo o domínio deste serviço — nenhum RF deste documento inclui criação de obrigação financeira, em nenhum dos dois sentidos; todo RF pressupõe um `billingId` já existente.

**Consequências:**
- Positivas: cada serviço evolui de forma independente; trocar de provedor de pagamento não exige nenhuma mudança no `Billing Service`, e vice-versa.
- Negativas: toda criação de Payment depende de uma consulta síncrona ao `Billing Service` (BD-11) — se aquele serviço estiver indisponível, nenhum Payment pode ser criado.

**Evolução:** revisar se um dia existir um cenário legítimo de Payment sem cobrança prévia (não previsto pelo documento funcional fornecido).

---

## BD-02 — Tipo do Payment (`RECEIVE`/`PAY`), Imutável Após a Criação

**Origem:** Documento funcional, seções 3, 7.

**Decisão:** todo Payment tem um `type` obrigatório, definido na criação e nunca alterado depois: `RECEIVE` (a empresa recebe dinheiro) ou `PAY` (a empresa paga dinheiro). O `type` do Payment não precisa coincidir estruturalmente com o `type` da cobrança relacionada (`RECEIVABLE`/`PAYABLE`, `billing-service` BD-18), mas espera-se, na prática, que `RECEIVE` sempre esteja associado a uma cobrança `RECEIVABLE` e `PAY` a uma `PAYABLE` — nenhuma validação cruzada dessa correspondência é feita nesta versão (assumido\*, ver Valores Assumidos em `12-acceptance-criteria.md`).

**Impacto:** `19-data-model.md` (`payments.type`, `CHECK`, sem coluna de atualização); `17-api-contracts.md` (campo obrigatório na criação).

**Consequências:**
- Positivas: elimina uma classe inteira de erro de negócio (inverter sentido de uma movimentação já em andamento).
- Negativas: nenhuma validação cruzada `payments.type` × `billing.type` nesta versão — uma aplicação chamadora poderia, em tese, criar um Payment `RECEIVE` para uma cobrança `PAYABLE`; mitigado apenas por convenção de uso, não por regra de banco/aplicação.

**Evolução:** considerar validar a correspondência `type` × cobrança relacionada, consultando o `Billing Service`, se o cenário de inconsistência se mostrar real em produção.

---

## BD-03 — Identificação: `paymentId` Interno vs. `providerPaymentId` Externo

**Origem:** Documento funcional, seção 5.

**Decisão:** todo `paymentId` é um UUID gerado pela aplicação na criação — o identificador interno, único, que os demais serviços da empresa devem persistir para referenciar um Payment. O `providerPaymentId` (identificador atribuído pelo provedor de pagamento) é mantido como referência auxiliar, nunca como identificador interno — nunca usado em rota (`/v1/payments/{id}` sempre usa `paymentId`).

**Impacto:** `19-data-model.md` (`payments.id` UUID PK; `payments.provider_payment_id` como coluna auxiliar, com índice); `17-api-contracts.md`; `contratos/18-event-contracts.md` (webhook localiza o Payment pelo `providerPaymentId`, mas todo evento publicado usa `paymentId`).

**Consequências:**
- Positivas: identificador estável mesmo que o provedor mude de formato/convenção entre versões de sua própria API, ou entre múltiplos provedores no futuro.
- Negativas: nenhuma — mesmo padrão já validado por `billing-service` (`billingId`) e demais serviços.

---

## BD-04 — Autenticação e Autorização Delegadas ao `auth-service`

**Origem:** Documento funcional, seções 30-31; `padrao-desenvolvimento.md`, seção 9.1.

**Decisão:** `Payment Service` nunca implementa login, emissão ou validação própria de JWT. Toda autenticação é via JWT emitido pelo `auth-service` (RS256, chave pública consultada e cacheada — ADR-001). Aplicações se autenticam via `client_id`/`client_secret`, obtendo Token de Serviço M2M (`POST /oauth2/v1/token/service`, `padrao-desenvolvimento.md` seção 9.3). Autorização por Perfil: `PAYMENT_READ`, `PAYMENT_CREATE`, `PAYMENT_CANCEL`, `PAYMENT_REFUND` (seção 31 do documento funcional) — nenhum concedido por padrão.

**Impacto:** `17-api-contracts.md` (todo endpoint exige um desses Perfis, exceto o webhook — ver BD-15 e Hotspot H02); `arquitetura/decisoes/ADR-001-...md`.

**Consequências:**
- Positivas: nenhuma reimplementação de autenticação; mesmo modelo de todos os serviços já documentados.
- Negativas: nenhuma — delegação total é o padrão organizacional desde `padrao-desenvolvimento.md` seção 9.1.

---

## BD-05 — Precisão Decimal para Valores Financeiros; `BRL` como Moeda Inicial

**Origem:** Documento funcional, seção 29.

**Decisão:** todo valor financeiro (`amount`) é armazenado com precisão decimal (`NUMERIC` no PostgreSQL) — nunca `float`, em nenhuma camada (banco, aplicação, serialização). `currency` é um campo explícito, restrito a `BRL` nesta versão — o modelo já suporta o campo, mas nenhuma lógica de conversão/multi-moeda existe.

**Impacto:** `19-data-model.md` (`payments.amount NUMERIC(14,2)`); `17-api-contracts.md`; `arquitetura/decisoes/ADR-014-...md`.

**Consequências:**
- Positivas: elimina uma classe inteira de bug de arredondamento financeiro desde o primeiro dia; mesma decisão já validada por `billing-service` (BD-04 daquele serviço).
- Negativas: nenhuma — é estritamente mais seguro que a alternativa, sem custo de complexidade adicional relevante.

**Evolução:** suportar múltiplas moedas quando houver necessidade real de negócio (seção 36 do documento funcional, "Não Implementar Inicialmente").

---

## BD-06 — Meio de Pagamento: Só `PIX` Implementado, Modelo Extensível

**Origem:** Documento funcional, seção 8.

**Decisão:** o campo `method` aceita, estruturalmente, `PIX`/`CREDIT_CARD`/`DEBIT_CARD`/`BANK_TRANSFER`/`BOLETO`/`OTHER`, mas nesta versão somente `PIX` é de fato implementado (validado, integrado ao provedor) — os demais valores existem no vocabulário de domínio, mas são rejeitados na criação (`400 METODO_NAO_SUPORTADO`) até que sejam implementados.

**Impacto:** `19-data-model.md` (`payments.method`, `CHECK IN ('PIX')` nesta versão — não o catálogo completo, para evitar sugerir suporte que não existe); `17-api-contracts.md`.

**Consequências:**
- Positivas: modelo já preparado para novos meios sem migração de schema quebrando compatibilidade — só ampliar o `CHECK` e implementar a integração.
- Negativas: nenhuma.

**Evolução:** implementar `CREDIT_CARD`/`DEBIT_CARD`/`BANK_TRANSFER`/`BOLETO`/`OTHER` somente quando houver necessidade real de negócio (seção 8 do documento funcional: "Implemente somente aqueles realmente utilizados").

---

## BD-07 — Catálogo de Status Fechado e Máquina de Transição

**Origem:** Documento funcional, seções 9-10.

**Decisão:** todo Payment tem um `status` dentro de um catálogo fechado de sete valores (`PENDING`, `PROCESSING`, `APPROVED`, `REJECTED`, `CANCELLED`, `REFUNDED`, `PARTIALLY_REFUNDED`), controlado por uma máquina de transição fechada (`09-domain-state-machines.md`). Nenhuma transição fora do catálogo explícito é permitida — em particular, `APPROVED → PENDING`, `APPROVED → REJECTED`, `REFUNDED → APPROVED` e `CANCELLED → APPROVED` são explicitamente proibidas pelo documento funcional (seção 10).

**Impacto:** `19-data-model.md` (`payments.status`, `CHECK`); `07-domain-services.md` (Serviço de Transição de Status).

**Consequências:**
- Positivas: elimina uma classe inteira de inconsistência de status por atualização direta.
- Negativas: nenhuma identificada.

---

## BD-08 — Estorno: Modelado no Catálogo de Status Desde a v1, Sem Endpoint Próprio de Iniciar Estorno

**Origem:** Documento funcional, seções 9, 24, 25, 35, 36.

**Contexto:** o documento funcional contém uma tensão textual real: a seção 9 inclui `REFUNDED`/`PARTIALLY_REFUNDED` no catálogo de status "a utilizar inicialmente"; a seção 25 inclui `PAYMENT_REFUNDED` no catálogo de eventos "a utilizar inicialmente"; mas a seção 24 abre com "Implemente posteriormente o estorno", e a lista explícita e exclusiva de "Primeira Versão" (seção 35, "Implemente somente: [...]") não inclui nenhum endpoint de estorno — a seção 36 ("Não Implementar Inicialmente") lista explicitamente "Estorno parcial", mas não repete "estorno total" ali, o que por si só não basta para inferir que o estorno total estaria em escopo, dado que a seção 35 já é uma lista exclusiva que não o menciona.

**Decisão:** os status `REFUNDED`/`PARTIALLY_REFUNDED` e o evento `PAYMENT_REFUNDED` existem no modelo de domínio desde a primeira versão (schema, máquina de estados, catálogo de eventos) — mas são alcançáveis nesta versão **somente de forma reativa**, se o próprio `Payment Provider` reportar um estorno via webhook (`POST /v1/payments/webhooks/{provider}`), iniciado fora deste serviço (ex.: estorno solicitado diretamente no banco/adquirente). O endpoint `POST /v1/payments/{id}/refund`, que permitiria a este serviço **iniciar** ativamente um estorno, fica fora do escopo da primeira versão, conforme a lista exclusiva da seção 35.

**Impacto:** `09-domain-state-machines.md` (transições para `REFUNDED`/`PARTIALLY_REFUNDED` documentadas, mas com gatilho único: webhook); `10-functional-requirements.md` (nenhum RF de "Solicitar Estorno" na primeira versão); `17-api-contracts.md` (endpoint de estorno documentado como fora de escopo da v1, contrato registrado para referência futura).

**Consequências:**
- Positivas: evita implementar uma capacidade (iniciar estorno) que a própria especificação, na leitura mais literal de sua lista de escopo exclusiva, não pede para a primeira versão.
- Negativas: um usuário/operador não tem, nesta versão, nenhuma forma de solicitar um estorno através do `Payment Service` — só reagir a um estorno já feito por outro canal.

**Evolução:** implementar `POST /v1/payments/{id}/refund` (total, depois parcial) quando houver necessidade real de negócio — ver Hotspot H03, decisão pendente de confirmação do usuário sobre esta leitura.

---

## BD-09 — Idempotência na Criação (`idempotencyKey`)

**Origem:** Documento funcional, seção 11.

**Decisão:** toda criação de Payment exige `idempotencyKey`. A mesma chave, reenviada pela mesma aplicação chamadora, nunca cria um segundo Payment — retorna o já existente. Escopo de unicidade assumido\* como `(idempotency_key, application)`, mesmo padrão já adotado por `billing-service` (BD-09 daquele serviço) — o documento funcional deste serviço não repete explicitamente "por aplicação" (seção 11), mas o exemplo (`ORDER-123456-PAYMENT`) segue a mesma convenção de nomenclatura já usada em `billing-service`.

**Impacto:** `19-data-model.md` (`UNIQUE (idempotency_key, application)`); `17-api-contracts.md`.

**Consequências:**
- Positivas: reenvio de requisição (timeout, retry de rede) nunca duplica uma movimentação financeira.
- Negativas: nenhuma.

---

## BD-10 — Idempotência de Webhook (`providerEventId`)

**Origem:** Documento funcional, seção 19.

**Decisão:** todo webhook recebido é identificado por um `providerEventId`, único (assumido\* como único por `provider`, já que provedores diferentes podem gerar identificadores de evento no mesmo formato/faixa). Um evento já processado nunca é reprocessado — a segunda chamada com o mesmo `providerEventId` retorna sucesso sem executar novamente a operação (seção 19 do documento funcional, textual).

**Impacto:** `19-data-model.md` (`payment_provider_events`, `UNIQUE (provider, provider_event_id)`); `contratos/18-event-contracts.md`.

**Consequências:**
- Positivas: reenvio de webhook pelo provedor (comportamento comum em integrações de pagamento, para garantir entrega) nunca aplica a mesma transição duas vezes.
- Negativas: exige uma tabela dedicada (`payment_provider_events`) só para deduplicação — aceito, é o mecanismo mais direto e auditável.

---

## BD-11 — Validação de Cobrança e Valor Disponível Antes da Criação

**Origem:** Documento funcional, seção 12.

**Decisão:** antes de criar um Payment, `Payment Service` confirma que o `billingId` informado existe e que `amount` não ultrapassa o valor disponível da cobrança — consulta síncrona ao `Billing Service`, assumida\* como `GET /v1/billings/{id}`, campo `remainingAmount`, endpoint já documentado por aquele serviço (`billing-service`, `contratos/17-api-contracts.md`, seção 2). O documento funcional deste serviço não especifica o contrato exato dessa consulta (seção 12 só diz "confirme que a cobrança existe" e "confirme que o valor não ultrapassa o valor disponível"); esta documentação reaproveita o contrato já publicado por `billing-service`, em vez de inventar um novo.

**Impacto:** `arquitetura/13-architecture.md` (dependência síncrona de `Billing Service` na criação); `10-functional-requirements.md` (RF-01).

**Consequências:**
- Positivas: nenhuma criação de Payment "órfã" (sem cobrança correspondente) ou que exceda o valor devido.
- Negativas: acoplamento temporal com `Billing Service` — se aquele serviço estiver indisponível, nenhum Payment pode ser criado, mesmo que o provedor esteja disponível.

**Evolução:** revisar se `billing-service` alterar o contrato de `GET /v1/billings/{id}` (ex.: renomear `remainingAmount`).

---

## BD-12 — Múltiplas Tentativas: Novo Payment por Tentativa, Nunca Reaproveitamento

**Origem:** Documento funcional, seção 23.

**Decisão:** cada tentativa de pagamento para uma mesma cobrança é um `Payment` próprio, imutável quanto ao seu resultado original. Um Payment `REJECTED` nunca é reaproveitado/reaberto para uma nova tentativa — uma nova tentativa sempre gera um novo `POST /v1/payments`, com novo `idempotencyKey`.

**Impacto:** `08-aggregates.md` (invariante: nenhum Payment tem seu resultado original alterado); `17-api-contracts.md` (ES-03/RF-03, consulta por `billingId` retornando múltiplos Payments).

**Consequências:**
- Positivas: histórico completo e nunca ambíguo de toda tentativa, mesmo as recusadas — auditoria fica trivial.
- Negativas: mais linhas na tabela `payments` por cobrança com múltiplas tentativas — aceito, é o comportamento explicitamente pedido pelo documento funcional.

---

## BD-13 — Abstração `PaymentProvider`

**Origem:** Documento funcional, seção 17.

**Decisão:** nenhuma regra de negócio deste serviço depende diretamente da API específica de um provedor de pagamento. Toda comunicação com o provedor passa por uma interface própria (`PaymentProvider`, camada `internal/infrastructure` — `padrao-desenvolvimento.md`, seção 2, Clean Architecture), permitindo múltiplas implementações concretas (`ProviderA`, `ProviderB`, ...) sem alterar o domínio. O provedor concreto ativo é escolhido por configuração — nenhuma lógica de negócio decide qual provedor usar nesta versão (só um provedor implementado, ver Hotspot H01).

**Impacto:** `arquitetura/13-architecture.md` (camada de abstração); `arquitetura/decisoes/ADR-015-...md`.

**Consequências:**
- Positivas: trocar de provedor, ou adicionar um segundo, não exige alterar nenhuma regra de domínio — só uma nova implementação da interface.
- Negativas: nenhuma — é puramente uma boa prática de desacoplamento, sem custo relevante.

**Evolução:** suportar múltiplos provedores simultâneos (escolha por regra de negócio — custo, disponibilidade, meio de pagamento) quando houver necessidade real (seção 36 do documento funcional, "Não Implementar Inicialmente").

---

## BD-14 — Comunicação HTTP Síncrona com Serviços Externos (Sem RabbitMQ)

**Origem:** Documento funcional, seção 39 ("Priorize uma implementação simples, pequena e adequada ao porte da empresa"); mesmo padrão já adotado por `billing-service` (ADR-010 daquele serviço).

**Contexto:** `padrao-desenvolvimento.md` (seção 2) fixa RabbitMQ como ponto de partida padrão sempre que um novo serviço precisar desacoplar produtor e consumidor de forma assíncrona. O documento funcional deste serviço não pede explicitamente HTTP síncrono (diferente de `billing-service`, que tinha uma instrução textual direta nesse sentido) — mas toda a descrição de fluxo (seções 13, 14, 18, 26) descreve chamadas diretas request/response entre `Payment Service` e `Billing Service`/`Person Service`/`Notification Service`, sem nenhuma menção a fila.

**Decisão:** `Payment Service` se comunica com `Billing Service`, `Person Service`, `Notification Service` e `Payment Provider` via chamada HTTP síncrona nesta versão — nenhuma fila para a comunicação de negócio. Todos os seis eventos de domínio do catálogo inicial (`PAYMENT_CREATED`, `PAYMENT_PROCESSING`, `PAYMENT_APPROVED`, `PAYMENT_REJECTED`, `PAYMENT_CANCELLED`, `PAYMENT_REFUNDED`) são modelados como eventos de domínio (para fins de nomenclatura/documentação, `18-event-contracts.md`), mas transportados via HTTP direto, não via mensageria — mesma decisão de `billing-service`.

Este serviço publica auditoria no exchange `audit.events` via RabbitMQ (uso exclusivo para auditoria), conforme `padrao-desenvolvimento.md` seção 17 e o `AuditEvent` canônico da `codepump-lib` (seção 17.3/18) — mesmo padrão de `organization-service` (ADR-011) e `alert-service` (ADR-010). Publicação best-effort, nunca bloqueia a operação de negócio. O desvio desta BD permanece válido **para a comunicação de negócio** (`Billing Service`/`Person Service`/`Notification Service`/`Payment Provider` seguem em HTTP síncrono, sem fila); RabbitMQ existe **exclusivamente para auditoria** (publicador, nunca consumidor). Ver BD-18, ADR-010, `contratos/18-event-contracts.md` e `arquitetura/15-infrastructure.md`.

**Impacto:** `arquitetura/13-architecture.md`; `arquitetura/15-infrastructure.md`; `contratos/18-event-contracts.md`; `requisitos/11-non-functional-requirements.md` (RNF, tensão registrada).

**Consequências:**
- Positivas: infraestrutura mais simples, adequada ao porte da empresa — sem operar um cluster RabbitMQ adicional só para este serviço; consistente com o padrão já assentado por `billing-service`.
- Negativas: acoplamento temporal entre os serviços — se `Billing Service`, `Person Service`, `Notification Service` ou o provedor estiverem indisponíveis no momento da chamada, a operação falha ou fica pendente, sem o amortecimento natural de uma fila.

**Evolução:** introduzir RabbitMQ quando a necessidade de desacoplamento/processamento assíncrono for real — mesmos critérios já registrados por `notification-service` (ADR-008 daquele serviço).

---

## BD-15 — Nenhum Dado Sensível Armazenado ou Registrado em Log

**Origem:** Documento funcional, seções 16, 32.

**Decisão:** `Payment Service` nunca armazena `client_secret`, senha, JWT, chave privada, CVV, senha bancária ou credencial de banco — em nenhuma tabela. Nenhum desses dados, nem dado bancário completo, nem credencial de acesso, aparece em log, sob nenhuma circunstância.

**Impacto:** `19-data-model.md` (nenhuma coluna para esses dados); `requisitos/11-non-functional-requirements.md`; `arquitetura/decisoes/ADR-009-...md` (padrão de logs).

**Consequências:**
- Positivas: elimina uma categoria inteira de vazamento de dado financeiro sensível por log ou backup de banco.
- Negativas: nenhuma.

---

## BD-16 — Dados do Recebedor via `Person Service`, Nunca Duplicados

**Origem:** Documento funcional, seção 15.

**Decisão:** para pagamentos `PAY`, `Payment Service` obtém os dados de destino (CPF/CNPJ, chave Pix, conta bancária) do `Person Service` — assumido\* como `GET /v1/persons/{personId}/receiving-accounts`, endpoint já documentado por aquele serviço (`person-service`, `contratos/17-api-contracts.md`, seção 9, Perfil `RECEIVING_READ`, `nunca concedido por padrão`). `Payment Service` nunca armazena esse dado além do estritamente necessário para executar a operação em curso — nenhuma tabela própria replica chave Pix/conta bancária.

**Impacto:** `08-aggregates.md` (invariante: nenhum dado financeiro de destino persistido); `19-data-model.md` (nenhuma coluna para esse dado); mesma restrição já registrada do lado de `billing-service` (BD-05/BD-19 daquele serviço, para a solicitação de pagamento outbound).

**Consequências:**
- Positivas: fonte única da verdade para dado cadastral/financeiro de pessoa (`Person Service`); nenhum risco adicional de vazamento por réplica desnecessária.
- Negativas: acoplamento temporal — pagamentos `PAY` dependem de uma chamada síncrona adicional ao `Person Service`, e falham se a Pessoa não tiver conta de recebimento cadastrada.

**Evolução:** revisar se `person-service` alterar o contrato de `GET /v1/persons/{id}/receiving-accounts`.

---

## BD-17 — Cada Serviço é Dono do Próprio Banco

**Origem:** Documento funcional, seção 26.

**Decisão:** `Payment Service` nunca acessa diretamente o banco de dados do `Billing Service`, nem qualquer outro serviço acessa diretamente o banco de dados do `Payment Service`. Toda comunicação entre serviços é via API (síncrona, nesta versão) ou evento — nunca acesso direto a schema/tabela de outro serviço.

**Impacto:** `arquitetura/13-architecture.md` (nenhuma conexão de banco cruzando serviços); `dominio/06-context-map.md`.

**Consequências:**
- Positivas: cada serviço evolui seu próprio schema livremente, sem quebrar outro serviço.
- Negativas: nenhuma — é o modelo já adotado por toda a organização.

`padrao-desenvolvimento.md` (seção 8.2) formaliza este princípio como padrão organizacional obrigatório para todos os serviços, citando `payment-service` nominalmente — ver **ADR-018** para o detalhamento completo (banco lógico `payment`, exclusivo, compartilhamento só na camada física). Esta BD permanece válida como registro da decisão de negócio; ADR-018 é a fonte arquitetural formal. O padrão de Health Check/Readiness Check/Identificação de Build (seção 12) também é adotado por este serviço — ver **ADR-019** (nenhuma BD prévia sobre o assunto a emendar).

---

## BD-18 — Auditoria de Operações Financeiras — Catálogo Fechado

**Origem:** Documento funcional, seção 34; `padrao-desenvolvimento.md`, seção 7.1.

**Decisão:** toda operação financeira relevante (`PAYMENT_CREATED`, `PAYMENT_APPROVED`, `PAYMENT_REJECTED`, `PAYMENT_CANCELLED`, `PAYMENT_REFUNDED`, `PAYMENT_PARTIALLY_REFUNDED`) gera um registro de auditoria com `paymentId`, `billingId`, `operation`, `application`, `actor`, `createdAt` — nunca dado financeiro sensível (chave Pix, conta bancária, CVV). Histórico de auditoria nunca é alterado depois de criado.

`PAYMENT_PARTIALLY_REFUNDED` consta deste catálogo porque a máquina de estados de BD-07/BD-08 permite `APPROVED → PARTIALLY_REFUNDED` de forma reativa; sem essa operação no catálogo, RF-09 não teria como registrar auditoria para essa transição.

Cada operação financeira do catálogo fechado é projetada em um `AuditEvent` canônico da `codepump-lib` e **publicada no `audit-service` via RabbitMQ** (`audit.events`, uso exclusivo para auditoria, `padrao-desenvolvimento.md` seção 17), como publicador, nunca consumidor — mesmo padrão de `organization-service` (ADR-011) e `alert-service` (ADR-010). Publicação best-effort, nunca bloqueia a operação de negócio; operações que falham também são auditadas (`success: false`). Mapeamento para `action`/`resource` (`PAYMENT`/`REFUND`/`APPROVE`/`REJECT`/`CANCEL`/`CREATE` sobre `resource: PAYMENT`) em `contratos/18-event-contracts.md`. Ver BD-14.

**Impacto:** `19-data-model.md` (`audit_logs`); `contratos/18-event-contracts.md`.

**Consequências:**
- Positivas: rastreabilidade completa de toda operação financeira relevante, sem risco de vazamento de dado sensível.
- Negativas: nenhuma.

---

## BD-19 — Correlation ID Propagado Entre Serviços

**Origem:** Documento funcional, seção 33.

**Decisão:** todo request aceita `X-Correlation-ID`; quando ausente, `Payment Service` gera um novo. O identificador é propagado em toda chamada saindo deste serviço — para `Billing Service`, `Payment Provider` e `Notification Service` — permitindo rastrear uma operação financeira completa, de ponta a ponta, através de múltiplos serviços.

**Impacto:** `requisitos/11-non-functional-requirements.md`; `arquitetura/decisoes/ADR-009-...md` (logs).

**Consequências:**
- Positivas: diagnóstico de incidente entre serviços deixa de depender de correlacionar timestamps manualmente.
- Negativas: nenhuma.

---

## BD-20 — Expurgo de Pagamentos `PENDING` Órfãos (`POST /internal/purge`)

**Origem:** ADR-021 (2026-08-14); padrão organizacional `POST /internal/purge` (`padrao-desenvolvimento.md`, seção 5).

**Decisão:** Pagamentos `PENDING` cuja Cobrança associada (`billingId`) não existe mais em `billing-service` são **removidos fisicamente** (`DELETE`) por uma operação interna `POST /internal/purge`, disparada periodicamente pelo `scheduler-service` (perfil `SCHEDULER`, fora de `/v1`, não exposta pelo Nginx). Elegibilidade: `status = PENDING` **e** Cobrança `billingId` **confirmada inexistente via M2M** ao `billing-service` **e** `createdAt < (agora − minPendingAge)` (salvaguarda anti-corrida, padrão assumido\* 24h, configurável `payment.purge.minPendingAgeHours`).

**Fail-safe:** se o `billing-service` estiver indisponível ou responder de forma inconclusiva, o Pagamento **não** é expurgado nesta execução — nunca se apaga sem confirmação positiva de que a fatura não existe; a próxima execução tenta de novo (idempotente). Nenhum outro status é elegível (`APPROVED`/`REJECTED`/`CANCELLED`/`REFUNDED` são consolidados, nunca expurgados). A operação é **idempotente** e **destrutiva** — registrada em auditoria (`operation = PAYMENT_PURGE`, sem dado financeiro); **nunca** remove registros de auditoria.

Esta é a **exceção explícita à ADR-006** (Pagamento imutável, sem remoção via API): a ADR-006 rege a API de negócio; o expurgo por retenção é manutenção interna disparada por máquina, prevista na seção 5 do padrão. É a primeira remoção física de Pagamento do serviço, restrita a `PENDING` órfão. Nunca toca em dado financeiro sensível — este serviço não o armazena.

**Impacto:** `arquitetura/decisoes/ADR-021-expurgo-pagamentos-pendentes-orfaos.md`; `requisitos/10-functional-requirements.md` (RF-10); `dominio/08-aggregates.md`, `dominio/09-domain-state-machines.md`, `dominio/06-context-map.md` (consulta M2M ao `billing-service`); `contratos/17-api-contracts.md` (seção 9 + Resumo de Rotas); `arquitetura/decisoes/ADR-020-interface-web-configuracao.md` (`payment.purge.minPendingAgeHours`); `scheduler-service` (nova Scheduled Task `payment-orphan-purge`).

**Consequências:**
- Positivas: pagamentos `PENDING` órfãos deixam de acumular sem resolução; fecha o ciclo com o expurgo de faturas do `billing-service` (uma fatura expurgada lá torna seu pagamento `PENDING` elegível aqui), sem acoplamento síncrono entre os dois expurgos.
- Negativas: depende da disponibilidade do `billing-service` para efetivar (por design, fail-safe); `minPendingAge` é assumido\* (Hotspot), a reavaliar conforme a janela real de coordenação `billing`↔`payment`.

O `POST /internal/purge` tem **dois** motivos de expurgo: (a) órfão-`PENDING` (esta BD) e (b) retenção `FREE` por `payments.purge_at <= now()` (BD-21, seção 26.8 do padrão). O critério (b) é **temporal** (não relacional) e **não** consulta o `billing-service`. Ambos coexistem no mesmo endpoint/execução — ver BD-21 e ADR-022.

---

## BD-21 — Planos, Recurso Externo `PAYMENT`, Retenção e Upgrade (Aplicação Alvo)

**Origem:** ADR-022 (2026-08-15); `padrao-desenvolvimento.md` seção 26 (o `payment-service`/`PAYMENT` é o **exemplo** da seção 26.10); `auth-service` ADR-026/BD-26.

**Decisão:** o `payment-service` é **aplicação alvo** — recebe operações **em nome de** um usuário no modelo de **dois tokens** (seção 9.4 — `SERVICE JWT` no `Authorization` + `USER JWT` no `X-User`) e aplica o **plano** do usuário (`FREE`/`PRO`/`MAX`; `MAX` = `PRO` no MVP) **lido direto de `profile.plan`** do único `profile` do `USER JWT` — o token é específico de uma aplicação (`profile.app` diz o contexto; seção 9.3/26.2). Regras:

- **Recurso externo `PAYMENT` (regra central):** configura-se `FREE → PAYMENT = não permitido`; `PRO`/`MAX → PAYMENT = permitido`. Ao receber uma operação de executar pagamento **em nome de um usuário** (`POST /v1/payments` com `X-User` + `SERVICE JWT`, seção 9.4), **valida o recurso `PAYMENT` contra o plano — lido direto de `profile.plan` do único `profile` do `USER JWT` — ANTES de qualquer efeito** (antes de cobrança/recebedor/provedor); `FREE` → `403 RECURSO_NAO_PERMITIDO_NO_PLANO`, nenhum Payment criado. Prioritário sobre o limite de registros.
- **Limite de registros:** `FREE` limita o **titular** (`payments.owner_user_id`, do **`sub` do `USER JWT`**) a `payment.maxRecords` Payments (configurável, valor assumido inicial `20`\*); contagem exclui os já expurgados; excedente → `403 LIMITE_PLANO_ATINGIDO`. `PRO`/`MAX` sem limite. Secundário ao gating de recurso (no MVP, `FREE` já é barrado pelo recurso).
- **Retenção temporária:** para titular `FREE`, `payments.purge_at = created_at + retentionDays` (configurável, assumido inicial `30`\*) na criação; só na entidade raiz `payments`; `NULL` para `PRO`/`MAX` ou sem titular. No MVP fica inerte (nenhum Payment `FREE` é criado, pois `PAYMENT` não é permitido) — definida desde já conforme a spec.
- **Upgrade** (`FREE→PRO`/`MAX`) via `POST /internal/users/{userId}/plan`: zera `purge_at` dos Payments do titular. **Downgrade** não atribui `purge_at` a registros existentes (MVP).
- **Expurgo:** o `POST /internal/purge` **existente** (ADR-021/BD-20) é **estendido** — passa a expurgar também os `payments` com `purge_at <= now()` e seus relacionados (`payment_status_history`, `payment_provider_events`), além dos órfãos-`PENDING`. **Nunca** um endpoint separado (seção 26.8). **Emenda ao ADR-006**.
- **Configuração/consulta:** valores configuráveis via `/config/plans` (ADR-020, `ADMIN`); `GET /plans` expõe planos/limites/retenção **e os recursos externos por plano** (`externalResources`).
- **Encadeamento:** se o `payment-service` precisar chamar outra aplicação alvo na mesma operação (mesmo contexto comercial), mantém o `X-User` **fixo** (o mesmo `USER JWT`, com seu único `profile`) e troca só o `Authorization` para o **seu próprio `SERVICE JWT`** (seção 9.4).
- **Fronteira:** o `payment-service` **aplica** recurso/limite/retenção/expurgo; o `auth-service` só **fornece** o contexto confiável (usuário/plano) — nunca aplica essas regras (seção 26.11).

**Titular vs. BD-16:** `payments.owner_user_id` guarda o **usuário** em nome de quem a operação corre (o **`sub` do `USER JWT`**, referência opaca de escopo de plano), **não** dado financeiro de destino — BD-16 (não replicar CPF/chave Pix/conta) permanece válida. É, ainda assim, a primeira identidade de usuário persistida por este serviço; mantida mínima (só o `sub` do `USER JWT`). Anotado como Hotspot em ADR-022.

**Impacto:** `arquitetura/decisoes/ADR-022-planos-retencao-upgrade.md`; `modelo-dados/19-data-model.md` (`payments.owner_user_id`/`purge_at`); `contratos/17-api-contracts.md` (nova seção 10 + gating na seção 1 + seção 9 estendida); `arquitetura/decisoes/ADR-006-payment-imutavel-sem-remocao.md` (emenda); `arquitetura/decisoes/ADR-021-expurgo-pagamentos-pendentes-orfaos.md` (segundo motivo de expurgo); `requisitos/10-functional-requirements.md` (RF-11) + `12-acceptance-criteria.md`.

**Consequências:**
- Positivas: regra comercial central (`FREE` não paga) aplicada no serviço dono da execução; gating antes de qualquer efeito colateral; expurgo reaproveita `/internal/purge` + `scheduler-service`.
- Negativas: introduz remoção física ampliada (emenda ao ADR-006) e a noção de "titular" (`owner_user_id`); limite/retenção ficam inertes no MVP (gating barra `FREE` antes); valores `20`\*/`30`\* são exemplos configuráveis.
