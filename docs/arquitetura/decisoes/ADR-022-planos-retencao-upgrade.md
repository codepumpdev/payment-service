# ADR-022 — Planos, Retenção e Upgrade (Aplicação Alvo)

- **Status:** Aceita
- **Data:** 2026-08-15

## Contexto

O `payment-service` passa a ser uma **aplicação alvo**: recebe operações **em nome de** um usuário no modelo de **dois tokens** (seção 9.4 — `SERVICE JWT` no `Authorization` + `USER JWT` no `X-User`) e precisa aplicar as **regras comerciais do plano** do usuário. O padrão organizacional está fixado em `padrao-desenvolvimento.md` **seção 26** (Planos, Retenção e Upgrade nas Aplicações Alvo); esta ADR é a **adoção local**, com os valores e entidades do domínio de Pagamentos.

O `auth-service` é a **fonte oficial** do estado comercial (plano + período de avaliação, ADR-026/BD-26 daquele serviço) e **fornece o contexto confiável** no `USER JWT`. **Quem aplica recurso externo/limite/retenção/expurgo é o `payment-service`** — nunca o `auth-service` (seção 26.11).

O `payment-service` é o **exemplo da spec** para o conceito de **Recurso Externo** (seção 26.10): `PAYMENT` é um recurso gated por plano — `FREE: PAYMENT = não permitido`; `PRO`/`MAX: PAYMENT = permitido`. Diferente do `person-service` (cadastro puro, sem recurso externo), aqui a regra **central** é a validação do recurso `PAYMENT` contra o plano **antes** de executar a movimentação financeira — a própria razão de o serviço adotar a seção 26.

Duas tensões específicas com decisões já vigentes deste serviço:

1. **ADR-006** decidiu que um Payment é **imutável e nunca removido** (nem física, nem logicamente); **ADR-021** já abriu a **primeira** exceção de remoção física (expurgo de `PENDING` órfãos, `POST /internal/purge`). A retenção `FREE` (seção 26.8) **amplia** esse caminho de remoção física — agora também para `payments.purge_at` vencido. Esta ADR **emenda** ADR-006 nesse ponto e **estende** o `/internal/purge` de ADR-021 (nunca cria um endpoint separado, seção 26.8).
2. **BD-16** decidiu que o `payment-service` **não persiste** dado financeiro de destino (CPF/CNPJ, chave Pix, conta) nem `personId` — obtém-os do `person-service` em tempo de execução. A nova coluna `payments.owner_user_id` guarda o **usuário** em nome de quem a operação corre (o **`sub` do `USER JWT`**, `X-User`), **não** um dado de destino: é uma **referência opaca de escopo de plano** (contagem de limite + escopo de retenção por usuário), não uma réplica de dado financeiro. A tensão é anotada como Hotspot e mantida mínima (ver Consequências).

## Decisão

### 1. Planos (seção 26.1)

`FREE`/`PRO`/`MAX` (enum `Plan` da `codepump-lib`). `MAX` tratado como `PRO` **nesta aplicação** — continua verdadeiro depois da emenda de 2026-08-20 à §26.1: o único privilégio concreto de `MAX` é o **Contexto dedicado**, aplicado pelo `context-service` (ADR-014 de lá), e não por aplicação alvo nenhuma. Valores **configuráveis** (seção 26.3), nunca em código. Valores iniciais deste serviço:

```text
FREE
    externalResources     PAYMENT = não permitido
    payment.maxRecords    20*      (por titular)
    retentionDays         30*
PRO / MAX
    externalResources     PAYMENT = permitido
    payment.maxRecords    ilimitado
    retentionDays         (sem retenção temporária)
```

`payment.maxRecords = 20`\* e `retentionDays = 30`\* são **valores assumidos** (exemplos da spec / convenção — `person-service` usa `30` para retenção); reais a confirmar via `/config/plans`. O recurso externo `PAYMENT` (não permitido em `FREE`) é o valor **decidido** pela spec (seção 26.10), não assumido.

### 2. Recurso externo `PAYMENT` (seção 26.10) — **regra central deste serviço**

Configura-se o recurso `PAYMENT` por plano: `FREE → PAYMENT = não permitido`; `PRO`/`MAX → PAYMENT = permitido`. Ao receber uma operação de **executar um pagamento em nome de um usuário** (`POST /v1/payments` reconhecido como on-behalf-of-user pela presença de `X-User` + `SERVICE JWT`, seção 9.4), o serviço, **antes** de qualquer efeito (antes da validação de cobrança de BD-11, da obtenção de recebedor de BD-16 e do envio ao provedor de BD-13):

1. lê o **`plan` do único `profile`** do **`USER JWT`** (`X-User`, `profile.plan`, via `TokenClaims` da `codepump-lib`) — o token é específico de uma aplicação e carrega **um único `profile`** (seção 9.3), então **não** há busca entre perfis nem header `X-User-App`; e lê o `sub` do usuário (do `USER JWT`);
2. carrega a configuração do recurso `PAYMENT` para o `plan`;
3. **rejeita** com `403 RECURSO_NAO_PERMITIDO_NO_PLANO` quando o recurso não é permitido no plano (`FREE`) — **nenhum** Payment é criado, **nenhuma** chamada a `Billing Service`/`Person Service`/provedor é feita;
4. permite prosseguir quando permitido (`PRO`/`MAX`).

Ambos os tokens são validados diretamente pelo serviço (assinatura via chave pública do `auth-service`, seção 9.1): o **`SERVICE JWT`** (`Authorization`) identifica a **aplicação chamadora** e suas **roles sobre `PAYMENT_SERVICE`** (Concessão BD-24, ex.: `PAYMENT_CREATE`); o **`USER JWT`** (`X-User`) identifica o **usuário** e traz o **plano** no seu único `profile` (`profile.plan`) — o token já é específico da aplicação (`profile.app`), informação **confiável** por estar no JWT assinado. A operação só prossegue quando os **dois contextos** (executor + usuário) são válidos.

Exemplo concreto: o `USER JWT` traz `profile.plan = FREE` → `PAYMENT` bloqueado (`403 RECURSO_NAO_PERMITIDO_NO_PLANO`). Se `profile.plan = PRO`/`MAX`, `PAYMENT` é permitido. O plano vem **direto** de `profile.plan`, sem header de contexto de origem.

A validação do recurso é **prioritária** sobre o limite de registros (§4): um titular `FREE` é barrado pelo recurso antes mesmo de contar registros. Operações **sistema-a-sistema** (só `SERVICE JWT` no `Authorization`, sem `X-User` — sem contexto de usuário) não passam por essa validação — é uma regra de contexto de usuário.

### 3. Titular do registro — `payments.owner_user_id`

Para contar registros por usuário (limite) e escopar a retenção por usuário (upgrade), cada Payment criado em contexto de usuário guarda o **titular**: nova coluna `payments.owner_user_id` (`UUID` NULL, referência **opaca** ao usuário do `auth-service`, padrão §8.2 — sem FK cruzando serviços), preenchida com o **`sub` do `USER JWT`** (`X-User`). O `owner_user_id` continua sendo o `sub` do `USER JWT` — **inalterado** pela mudança para o modelo de `profile` único (que só muda de onde vem o `plan` — agora `profile.plan` —, não de onde vem a identidade do titular). `NULL` para Payments criados fora de contexto de usuário (ex.: `PAY` disparado por `Billing Service`/sistema-a-sistema, só `SERVICE JWT`), que ficam fora de recurso/limite/retenção. **Não** é dado financeiro de destino (BD-16 preservada) — só escopo de plano.

### 3.1 Sem validação de `X-User-App`

Não há header `X-User-App` nem erro `403 CONTEXTO_APLICACAO_INVALIDO`: o contexto de aplicação vem de `profile.app` e o plano (inclusive o gating de `PAYMENT`) de `profile.plan` do único `profile` do `USER JWT` (§2).

### 4. Limite de registros (seção 26.5)

Ao **criar** um Payment em contexto de usuário `FREE` (e já tendo passado a validação de recurso §2): identifica o titular no `USER JWT` (`X-User`, `sub`), obtém o plano de `profile.plan` (§2), carrega a configuração, **conta os Payments do titular** (`owner_user_id = sub do USER JWT`, **excluindo** os já expurgados) e **rejeita** com `403 LIMITE_PLANO_ATINGIDO` quando a contagem já é `>= payment.maxRecords`. `PRO`/`MAX` não têm esse limite. Regra **secundária** ao gating de recurso (§2) — no plano `FREE` a rejeição por recurso ocorre primeiro; o limite existe para o caso de um plano futuro que **permita** `PAYMENT` mas ainda limite a quantidade.

### 5. Retenção temporária — `payments.purge_at` (seção 26.6)

- `purge_at` (`TIMESTAMPTZ` NULL) fica **somente** na entidade raiz `payments`. As tabelas relacionadas (`payment_status_history`, `payment_provider_events`) **não** têm `purge_at`.
- Para titular `FREE`, `purge_at = created_at + retentionDays` no momento da criação. `PRO`/`MAX` (ou fora de contexto de usuário): `purge_at = NULL`.
- Consequência de §2: com `PAYMENT` não permitido em `FREE`, **nenhum** Payment `FREE` é criado no MVP — logo `purge_at` só se torna efetivo se um plano vier a **permitir** `PAYMENT` mantendo retenção temporária. A coluna e a regra ficam definidas desde já (a spec pede `purge_at` na raiz), sem depender dessa configuração futura.

### 6. Upgrade / Downgrade — `POST /internal/users/{userId}/plan` (seção 26.7)

- **Upgrade** (`FREE → PRO`/`MAX`): valida a solicitação interna; atualiza o plano aplicável; localiza os Payments do titular com `purge_at IS NOT NULL`; **zera `purge_at`** (`NULL`); mantém os dados permanentes. O chamador **não** informa quais registros. É o par do fluxo de pagamento (a aplicação de pagamento atualiza o plano na fonte oficial `auth-service` **e** chama este endpoint em cada aplicação alvo, seção 26.7).
- **Downgrade** (`PRO`/`MAX → FREE`): **não** atribui `purge_at` a registros existentes (MVP — retenção só nos novos registros criados sob `FREE`).

### 7. Expurgo — `POST /internal/purge` (seções 26.8/26.9) — **EXTENSÃO do endpoint de ADR-021**

O expurgo de retenção `FREE` é feito **dentro** do `/internal/purge` já existente (ADR-021) — **nunca** um endpoint separado (seção 26.8). O mesmo endpoint passa a ter **duas razões** de expurgo, avaliadas na mesma execução disparada pelo `scheduler-service` (perfil `SCHEDULER`, seção 26.9):

- **(a) Órfão-`PENDING` (ADR-021, pré-existente):** `status = PENDING` **e** Cobrança `billingId` confirmada inexistente via M2M ao `billing-service` **e** `createdAt < (agora − minPendingAge)`. Fail-safe: na dúvida, não expurga.
- **(b) Retenção `FREE` (novo, esta ADR):** `payments.purge_at <= now()`, **independente** de status ou de `billing-service` — a retenção é uma decisão temporal já registrada em `purge_at`, não relacional. Para cada Payment elegível, remove primeiro os relacionados (`payment_status_history`, `payment_provider_events`) e depois o próprio Payment, respeitando o `ON DELETE RESTRICT` existente pela **ordem de remoção** (não é preciso trocar para `CASCADE`). Registra o resultado (`AuditEvent`, `operation = PAYMENT_PURGE`, sem dado financeiro).

É **remoção física** (seção 5) — **emenda ao ADR-006**, restrita a estes dois caminhos de retenção. **Nunca** remove registros de auditoria (vivem em `audit-service`, seção 17) — mesmo tratamento já fixado por ADR-021. A resposta soma os dois motivos (ver contrato em `17-api-contracts.md`, seção 9).

### 8. Endpoints de consulta/configuração

- `GET /plans` — leitura **pública** das configurações de plano, **expondo os recursos externos por plano** (`externalResources`), além de limites e retenção. Não expõe interno (seção 26.4). Ex.: `FREE → externalResources: [{ resource: "PAYMENT", allowed: false }]`.
- `/config/plans` — administração da configuração de planos, sob a API de Configuração já adotada por este serviço (**ADR-020**, `GET /admin/config`), perfil **`ADMIN`** (seção 9.1). Validação no backend; auditoria de mudança (`AuditEvent`, `resource = CONFIG`); nunca expõe sensíveis.

### 9. Fronteira (seção 26.11)

O `payment-service` **aplica** recurso externo/limite/retenção/expurgo; o `auth-service` só **fornece** o contexto confiável (usuário/plano no `USER JWT`) — **nunca** aplica essas regras.

## Consequências

### Positivas

- A regra comercial mais importante deste serviço — **não deixar um usuário `FREE` executar pagamento** — é aplicada na fronteira certa (o serviço que executa a movimentação), com o `auth-service` só fornecendo contexto.
- O gating de recurso `PAYMENT` é uma barreira **antes** de qualquer efeito colateral (cobrança/recebedor/provedor) — falha barata e sem rastro.
- `purge_at` só na raiz simplifica o modelo; o expurgo **reaproveita** o `/internal/purge` + `scheduler-service` já existentes (ADR-021), sem novo endpoint nem nova Scheduled Task obrigatória.

### Negativas / Hotspots

- **Remoção física ampliada** (emenda ao ADR-006 / extensão de ADR-021) — agora há dois motivos de expurgo no mesmo endpoint; qualquer alargamento (ex.: LGPD, expurgo de consolidados) é decisão separada.
- **`owner_user_id` vs. BD-16 (Hotspot\*):** BD-16 mantém o serviço **sem** dado financeiro de destino persistido. `owner_user_id` **não** é dado de destino — é uma referência opaca de **escopo de plano** (contagem/retenção por usuário). Ainda assim, é a **primeira** identidade de usuário persistida por este serviço (antes só o `personId` transitório, nunca gravado). Mantida **mínima** (só o `sub` do `USER JWT`, sem nome/documento/contato); confirmar com o negócio se persistir o titular é aceitável ou se a contagem/retenção deveria ser resolvida sem gravá-lo.
- **Retenção efetivamente inerte no MVP:** como `FREE` **não permite** `PAYMENT`, nenhum Payment `FREE` é criado — `payment.maxRecords`/`retentionDays`/`purge_at` só passam a ter efeito se um plano futuro permitir `PAYMENT` com limite/retenção. As regras ficam definidas (a spec pede), mas sem exercício prático no MVP — anotado para não sugerir cobertura que hoje não roda.
- **`payment.maxRecords = 20`\* e `retentionDays = 30`\*** são exemplos assumidos — **configuráveis**; valores operacionais reais a confirmar.

## Critérios para reavaliar

- Se um plano vier a **permitir** `PAYMENT` mantendo limite/retenção (ex.: `FREE` com N pagamentos/mês) — aí o limite (§4) e a retenção (§5) deixam de ser inertes e passam a exigir cobertura de teste real.
- Se persistir o titular (`owner_user_id`) se mostrar em tensão com BD-16 na prática — avaliar contagem/retenção sem gravar o usuário.
- Se a retenção precisar valer para registros **existentes** após downgrade — hoje só novos registros `FREE` (seção 26.7).

## Nota de integração

- `padrao-desenvolvimento.md` seções 9.3/9.4 (dois tokens `USER`+`SERVICE`; `USER JWT` específico de uma aplicação, um único `profile`; `X-User-App` **removido**) e 26.2/26.10/26.11 (plano lido **direto** de `profile.plan`); seção 26.10 usa `payment-service`/`PAYMENT` como exemplo; `auth-service` ADR-026/BD-26 (fonte oficial do plano; `DELEGATE`/ADR-025 **removido** — seção 9.4); `codepump-lib` ADR-010 (`TokenClaims`/`Profile`/`Plan`).
- `dominio/03-business-decisions.md` — **BD-21** (recurso externo `PAYMENT`/limite/retenção/expurgo/fronteira).
- `modelo-dados/19-data-model.md` — `payments.owner_user_id`, `payments.purge_at`.
- `contratos/17-api-contracts.md` — nova seção 10 (`GET /plans`, `/config/plans`, `POST /internal/users/{userId}/plan`) + gating `PAYMENT` na seção 1 (plano lido de `profile.plan`; exemplos on-behalf só com `Authorization` + `X-User`, sem `X-User-App`; erro `403 CONTEXTO_APLICACAO_INVALIDO` **removido**); `POST /internal/purge` (seção 9) **estendido**; Resumo de Rotas.
- `dominio/04-ubiquitous-language.md` — Plano / Titular / Recurso Externo (`PAYMENT`) / `purgeAt` / Expurgo (operação em nome de usuário com dois tokens `USER`+`SERVICE`, seção 9.4).
- `arquitetura/decisoes/ADR-006-payment-imutavel-sem-remocao.md` — emenda (remoção física via expurgo de retenção `FREE`, além do órfão-`PENDING`).
- `arquitetura/decisoes/ADR-021-expurgo-pagamentos-pendentes-orfaos.md` — nota de que o `/internal/purge` passa a expurgar também dados de retenção `FREE` (segundo motivo).
- `arquitetura/decisoes/ADR-020-api-configuracao.md` — `/config/plans` como especialização do `/admin/config`.
- `requisitos/10-functional-requirements.md` (**RF-11**, plano de `profile.plan`) + `12-acceptance-criteria.md` (cenário de gating por `profile.plan`).
- `scheduler-service` — a Scheduled Task `payment-orphan-purge` (ADR-021) passa a cobrir também o expurgo de retenção `FREE` no mesmo `POST /internal/purge` (nenhuma nova task obrigatória).
