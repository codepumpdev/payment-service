# Roadmap do Projeto — payment-service

> **Desatualizado em 2026-09-07 — o conceito de Contexto foi removido da plataforma.**
>
> O que neste documento descreve Contexto **não vale mais**: as etapas que planejavam adotar, migrar ou operar Contextos.
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


> Etapas referem-se às seções de `padrao-desenvolvimento.html` (codepump).
> Status possíveis: `Pendente` · `Em andamento` · `Bloqueado` · `Feito`
> No companheiro visual (`roadmap.html`), cada item aparece como: 🟢 Feito · 🟡 Incompleto · 🔵 Sem dependências pendentes, pronto para começar · ⚪ Bloqueado por dependência

**Última atualização:** 2026-08-15 (`USER JWT` específico de uma aplicação — um único `profile`; header `X-User-App` **removido** e plano/gating de `PAYMENT` lidos direto de `profile.plan`; erro `CONTEXTO_APLICACAO_INVALIDO` removido; `padrao-desenvolvimento.md` seção 9.3/9.4/26.2)

---

## Próximo Passo

**Toda a documentação inicial (etapas 2 a 8) foi escrita em um único levantamento**, a partir do documento funcional fornecido pelo usuário (2026-08-13) e da adoção direta do padrão organizacional (`padrao-desenvolvimento.md`) para tudo que já estava fixado (stack Go, autenticação delegada a `auth-service`, OpenBao, logs, padrão de resposta de API, versionamento, envelope de erro) — mesmo perfil de `billing-service`: nenhum Hotspot de infraestrutura/autenticação precisou ser aberto.

Este serviço tem duas particularidades que o distinguem de todos os demais já documentados: (1) diferente de `billing-service` (que representa a obrigação financeira e desvia do padrão de mensageria por HTTP síncrono), `payment-service` executa a movimentação financeira real — é o único serviço com um agregado explicitamente **imutável** após a criação (`Payment` nunca é editado nem removido, ADR-006 — sem análogo de "remoção lógica" nenhum, desviando também desse padrão organizacional, mas na direção de mais rigidez, não menos); (2) depende de um `Payment Provider` externo cujo nome real ainda não foi escolhido pela empresa — isso está na raiz de dois dos três Hotspots abertos (H01, H02).

Com Domínio, Requisitos, Arquitetura, Contratos, Modelo de Dados e Planejamento completos, `Implementação/Código` (etapa 9) tem todas as suas dependências satisfeitas e pode começar — desde que a integração com o `Payment Provider` (E2, `20-epics.md`) seja implementada atrás da abstração `PaymentProvider` (BD-13, ADR-015), isolando o maior risco de retrabalho do plano.

Dois padrões organizacionais (`padrao-desenvolvimento.md`, seções 8.2 e 12) foram adotados neste serviço — banco de dados exclusivo (ADR-018, já era de fato assim) e Health Check/Readiness Check/Identificação de Build (ADR-019, `GET /health`/`GET /ready` nunca antes formalizados). Confirmado, na mesma ADR-019, que este serviço já está em conformidade com o terceiro padrão organizacional da mesma data (Tarefas Agendadas via `scheduler-service`, seção 13) — nenhum job interno a migrar (`contratos/18-event-contracts.md`). Um novo Hotspot (H04 — se `Billing Service`/`Person Service` são dependências obrigatórias do `/ready`, dado que a chamada síncrona bloqueante de cada um é restrita a uma fração dos endpoints) foi registrado, reaproveitando o precedente já aberto por `person-service` (Hotspot H05 daquele serviço) para o mesmo tipo de ambiguidade. `Implementação/Código` (etapa 9) continua com todas as dependências satisfeitas — a mudança não adiciona nem remove pré-requisito, só formaliza contratos que a implementação já precisaria seguir. Ver "Concluído", abaixo, para o detalhe completo.

Referência: `dominio/01-event-storming-big-picture.md` (Hotspots), `planejamento/21-user-stories.md`

---

## Status por Etapa

| # | Etapa | Status |
|---|-------|--------|
| 2 | Descoberta do Negócio | Feito |
| 3 | Definição do Domínio | Feito *(Bounded Contexts, Context Map, Entidades, Value Objects, Agregados, Serviços de Domínio, Eventos, Ciclos de Vida — `01-event-storming-big-picture.md` a `09-domain-state-machines.md`; 19 Decisões de Negócio, 9 Event Stories)* |
| 4 | Requisitos | Feito *(9 Funcionais, 12 Não Funcionais e Critérios de Aceite — `10-functional-requirements.md` a `12-acceptance-criteria.md`)* |
| 5 | Arquitetura | Feito *(Componentes, Infraestrutura, Autenticação/Autorização, 19 ADRs — ADR-018/ADR-019 adicionadas em 2026-08-13 — `13-architecture.md`, `15-infrastructure.md`, `arquitetura/decisoes/`)* |
| 6 | Contratos | Feito *(APIs — `17-api-contracts.md`, 8 seções — Health/Ready/Build, ADR-019, adicionada em 2026-08-13; eventos internos + comunicação HTTP síncrona com `Billing Service`/`Person Service`/`Payment Provider` — `18-event-contracts.md`, sem Message Broker, ADR-010)* |
| 7 | Modelo de Dados | Feito *(quatro tabelas — `payments`, `payment_status_history`, `payment_provider_events`, `audit_logs` — `19-data-model.md`; migrações sugeridas, execução real fica para Implementação)* |
| 8 | Planejamento do Desenvolvimento | Feito *(4 Épicos, 8 Histórias — RF-04 incorporada à História de RF-01, sem História própria — `20-epics.md`, `21-user-stories.md`)* |
| 9 | Implementação | Pendente |
| 10 | Testes | Pendente |
| 11 | Segurança | Feito *(Autenticação/Autorização delegadas a `auth-service` — ADR-001; Secrets — OpenBao, ADR-008; Auditoria — BD-15/BD-18; dados sensíveis nunca armazenados — BD-16, RNF-12)* |
| 12 | Observabilidade | Parcial *(Logs — formato e armazenamento resolvidos, ADR-009; métricas de aplicação não especificadas nesta versão)* |
| 13 | CI/CD | Pendente |
| 14–18 | Ambientes, Homologação, Deploy, Operação, Evolução | Pendente (exceto o próprio processo de evolução da documentação, que já está rodando) |

---

## Dependências

> Formato: `Etapa/Item` depende de `Etapa/Item`. Mesma estrutura de `billing-service`/`person-service`/`storage-service`.

| Item | Depende de |
|------|------------|
| Domínio/Context Map | Domínio/Bounded Contexts |
| Domínio/Agregados | Domínio/Entidades, Domínio/Value Objects |
| Requisitos/Critérios de aceite | Requisitos/Funcionais |
| Contratos/APIs | Requisitos/Funcionais, Arquitetura/Componentes |
| Contratos/Contratos de evento | Domínio/Eventos de domínio |
| Modelo de Dados/Tabelas | Domínio/Entidades, Arquitetura/Banco de dados |
| Planejamento/Épicos | Requisitos/Funcionais |
| Planejamento/Histórias | Planejamento/Épicos, Requisitos/Critérios de aceite |
| Implementação/Código (E1, E4) | Planejamento/Histórias, Contratos/APIs, Modelo de Dados/Tabelas |
| Implementação/Código (E2, E3) | Implementação/Código (E1); resolução de H01/H02 para integração real com o provedor |
| Testes/* | Implementação/Código |
| Observabilidade/Métricas | Implementação/Código |
| CI/CD/Build | Implementação/Código |
| Ambientes/HML | Ambientes/DEV |
| Ambientes/PRD | Ambientes/HML |
| Homologação/* | CI/CD/Testes automáticos, Ambientes/HML |
| Deploy/Checklist pré-deploy | Homologação/Aprovação |
| Operação/Monitoramento | Observabilidade/Alertas, Ambientes/PRD |

---

## Hotspots Abertos

- [ ] H01 — Qual provedor de pagamento (`Payment Provider`) será efetivamente integrado — a especificação usa nomes ilustrativos ("Provider A", "Provider B"), nenhum foi escolhido. Assumido provisoriamente como `PROVIDER_A`. Ver `dominio/01-event-storming-big-picture.md`.
- [ ] H02 — Mecanismo exato de validação de autenticidade de um webhook de confirmação — depende diretamente de H01 (cada provedor tem seu próprio esquema de assinatura).
- [ ] H03 — Se o estorno relatado de forma reativa pelo provedor (fora de qualquer endpoint deste serviço) está mesmo dentro do escopo desta versão, ou se os status/eventos de estorno deveriam ficar totalmente fora do MVP — o documento funcional tem trechos que se tensionam (seção 9/25 incluem os status/catálogo de estorno "desde o início"; seção 24/35 dizem "implemente posteriormente"). Resolvido nesta rodada como leitura assumida (BD-08, ADR-016): estorno reativo faz parte do domínio do MVP; nenhum endpoint de iniciar estorno é implementado. Ver `12-acceptance-criteria.md`, Valores Assumidos.
- [ ] H04 — Se `Billing Service` (e, com restrição ainda maior, `Person Service`) são dependências obrigatórias do `GET /ready` deste serviço — cada um tem uma chamada síncrona genuinamente bloqueante (BD-11/BD-16), mas restrita ao endpoint de criação (e, para `Person Service`, só ao subtipo `PAY` dentro dele). A regra organizacional (`padrao-desenvolvimento.md`, seção 12.3) não cobre esse cenário de "bloqueante só para um subconjunto de endpoints" — mesma lacuna já identificada por `person-service` (Hotspot H05 daquele serviço). ADR-019 decide, por ora, não incluir nenhum dos dois no `/ready`, reaproveitando o mesmo raciocínio.

Nenhum dos quatro bloqueia o início da etapa de Implementação para E1 (Payment) e E4 (Auditoria); **H01/H02 bloqueiam de fato a integração real do E2** (Confirmação do Provedor) e, por consequência de runtime, do E3 (Integração com Billing Service) — mitigado implementando E2 atrás da abstração `PaymentProvider` (BD-13, ADR-015) desde o início, para que a escolha real do provedor não exija redesenho do domínio. H04 não bloqueia nada — é uma questão de classificação de `/ready`, não de comportamento funcional.

---

## Concluído

### 2026-08-20 — Adoção do padrão de Contexto (ADR-024)

O banco deixa de vir da configuração e passa a vir da identidade autenticada (§28 do padrão). O serviço é **contextual por inteiro**: `payments`, `payment_status_history`, `payment_provider_events` e `audit_logs` vivem no banco do Contexto.

**Ponto aberto que a adoção revelou:** o webhook do provedor não chega com o `USER JWT` do titular, então não há de onde ler o Contexto — e não se pode varrer bancos procurando a transação. A saída preferida é carregar o Contexto na referência enviada ao provedor, que volta no webhook; a alternativa é um índice global `transação → Contexto`, que tornaria o serviço misto. Enquanto isso não for fechado, o webhook não opera — e é melhor assim do que resolvido por um banco padrão.

Referências: `arquitetura/decisoes/ADR-024-adocao-do-padrao-de-contexto.md`, `codepump/docs/padrao-desenvolvimento.md` §28.7.

---

### 2026-08-15 — ADR-022: Planos, Recurso Externo `PAYMENT`, Retenção e Upgrade (Aplicação Alvo)

O `payment-service` é **aplicação alvo** e adota o padrão organizacional de planos (`padrao-desenvolvimento.md` seção 26), do qual é o **exemplo da spec** para **Recurso Externo** (seção 26.10). Recebe operações **em nome de** um usuário no modelo de **dois tokens** (seção 9.4 — `Authorization: Bearer <SERVICE_JWT>`, a aplicação chamadora, + `X-User: <USER_JWT>`, o usuário); não existe token `DELEGATE`. O `USER JWT` é **específico de uma aplicação** (um único `profile`): o **plano** — e portanto o **gating de `PAYMENT`** — é lido **direto de `profile.plan`**, e `profile.app` dá o contexto de aplicação (JWT assinado). Não há header `X-User-App` nem o erro `403 CONTEXTO_APLICACAO_INVALIDO`.

Regras comerciais do domínio de Pagamentos (ADR-022/BD-21/RF-11):

- **Recurso externo `PAYMENT` (regra central):** `FREE → PAYMENT = não permitido`; `PRO`/`MAX → permitido`, configurável. Ao receber `POST /v1/payments` em nome de usuário (`X-User` + `SERVICE JWT`), **valida o recurso — plano lido de `profile.plan` do único `profile` do `USER JWT` — antes de qualquer efeito**; `FREE` → `403 RECURSO_NAO_PERMITIDO_NO_PLANO` (nenhum Payment criado, nenhuma chamada externa).
- **Limite de registros:** `FREE` → `payment.maxRecords` por titular (assumido `20`\*, configurável; excedente → `403 LIMITE_PLANO_ATINGIDO`); `PRO`/`MAX` sem limite — secundário ao gating.
- **Retenção temporária:** `payments.purge_at = created_at + retentionDays` (assumido `30`\*, só na entidade raiz) — inerte no MVP, pois `FREE` não permite `PAYMENT`.
- **Titular:** nova coluna `payments.owner_user_id` = **`sub` do `USER JWT`**, referência opaca de escopo de plano — **não** dado financeiro de destino (BD-16 preservada; anotado como Hotspot em ADR-022, primeira identidade de usuário persistida, mantida mínima).
- **Upgrade e expurgo:** `POST /internal/users/{userId}/plan` zera `purge_at` do titular; o `POST /internal/purge` **existente** (ADR-021) é **estendido** com um segundo motivo (retenção `FREE`), nunca um endpoint separado (seção 26.8) — remoção física, emenda ao ADR-006.
- **Consulta/config:** `GET /plans` (leitura pública, expõe `externalResources`) e `/config/plans` (ADR-020, perfil `ADMIN`). **Fronteira:** o `payment-service` aplica as regras; o `auth-service` só fornece o contexto (BD-26 daquele serviço).

Propagado: `arquitetura/decisoes/ADR-022-planos-retencao-upgrade.md` (nova ADR), `dominio/03-business-decisions.md` (BD-21 + nota em BD-20), `modelo-dados/19-data-model.md` (`payments.owner_user_id`/`purge_at` + migração `000005`), `contratos/17-api-contracts.md` (nova seção 10 — `GET /plans`, `/config/plans`, `POST /internal/users/{userId}/plan`; gating `PAYMENT` na seção 1; seção 9 estendida; Resumo de Rotas), `arquitetura/decisoes/ADR-006-payment-imutavel-sem-remocao.md` (segundo caminho de remoção física), `arquitetura/decisoes/ADR-021-expurgo-pagamentos-pendentes-orfaos.md` (segundo motivo de expurgo), `dominio/04-ubiquitous-language.md` (Operação em nome de usuário + Recurso Externo `PAYMENT`/Plano/Titular/`purgeAt`/Expurgo), `requisitos/10-functional-requirements.md` (RF-11), `12-acceptance-criteria.md` (cenários RF-11 + Valores Assumidos + Rastreabilidade), este roadmap. Cross-service: `scheduler-service` — a Scheduled Task `payment-orphan-purge` (ADR-021) cobre também a retenção `FREE` no mesmo endpoint (nenhuma nova task obrigatória). Cross-ref: `padrao-desenvolvimento.md` seção 9.3/9.4/26 (`payment-service`/`PAYMENT` é o exemplo de recurso externo); `auth-service` ADR-026/BD-26 (fonte do plano; `DELEGATE`/ADR-025 removido); `codepump-lib` (`TokenClaims`/`Profile`/`Plan`).

---

### 2026-08-14 — ADR-020: API de Configuração (`/admin/config`)

Adoção do padrão organizacional de **API de Configuração** (`padrao-desenvolvimento.md` seção 23; `codepump/docs/padroes-implementacao/padrao-api-config.md`), obrigatório para todo serviço com configuração programável e sem UI administrativa própria — `payment-service` está nominalmente na lista abrangida.

**Nova ADR — ADR-020** (`arquitetura/decisoes/`): formaliza a endpoint `GET /admin/config`, servida pela própria aplicação Go (`net/http` + `html/template` + HTMX + CSS, sem SPA, recursos em `internal/web/` via `embed`), protegida por perfil administrativo validado no backend (seção 9), contraparte humana do `/props` (seção 16). Enumera as categorias de configuração reais (Aplicação, Banco, Serviços internos, Serviços externos, Mensageria, Operacional), distinguindo read-only (host/porta/build/`environment`/banco lógico) de editável (timeouts de chamada HTTP — ADR-010, provedor de pagamento ativo — ADR-015, timeout do Readiness Check), com efeito imediato × exige reinicialização sinalizado. Segredos (senha do banco, `client_secret` M2M, chave/segredo de webhook do provedor, credencial do RabbitMQ) **nunca** exibidos — OpenBao (ADR-008), só indicador booleano. Mudanças de configuração auditadas via `AuditEvent` canônico (`resource = CONFIG`, `data` com propriedade + valor anterior/novo, nunca sensível — seção 17). Sem API paralela: reutiliza os GET padronizados (seção 20). Fase de documentação — fixa o escopo/padrão da tela, não o HTML real.

Propagado para: `produto/visao-do-produto.md` (nota na seção 6 — Segurança), `planejamento/21-user-stories.md` (exceção ao "Frontend N/A" da convenção), este roadmap.

Referências: `arquitetura/decisoes/ADR-020-api-configuracao.md`, `codepump/codepump/docs/padrao-desenvolvimento.md` (seção 23), `codepump/codepump/docs/padroes-implementacao/padrao-api-config.md`.

---

### 2026-08-14 — Auditoria Centralizada via `audit-service`: RabbitMQ uso exclusivo para auditoria

Alinhamento ao padrão organizacional de Auditoria Centralizada (`codepump/codepump/docs/padrao-desenvolvimento.md`, seção 17 — obrigatório para `payment-service`, citado nominalmente na seção 17). Até aqui, `payment-service` auditava suas operações financeiras **apenas** via eventos de domínio despachados em memória e consumidos pelo módulo de Auditoria interno (BC-02), sem publicar em nenhum broker (ADR-010). A partir desta data, o serviço passa a **publicar cada operação financeira relevante no exchange `audit.events` via RabbitMQ**, no formato do `AuditEvent` canônico da `codepump-lib` (seções 17.3/18) — RabbitMQ **usado exclusivamente para auditoria** (publicador, nunca consumidor; nenhuma fila própria de negócio), mesmo padrão de `organization-service` (ADR-011) e `alert-service` (ADR-010). A comunicação de negócio (`Billing Service`/`Person Service`/`Notification Service`/`Payment Provider`) permanece em HTTP síncrono — o desvio de ADR-010 segue válido, restrito à mensageria de negócio. Como este serviço movimenta dinheiro, a auditoria centralizada de `PAYMENT`/`REFUND`/aprovação/rejeição/cancelamento é de alta relevância de rastreabilidade (BD-18).

Os documentos são consolidados para o estado vigente (`padrao-desenvolvimento.md`, seção 1).

Mapeamento do catálogo fechado (BD-18) para o `AuditEvent` (`application: payment-service`, `resource: PAYMENT`, `resourceId: paymentId`): `PAYMENT_CREATED`→`CREATE`; `PAYMENT_APPROVED`→`APPROVE`; `PAYMENT_REJECTED`→`REJECT`; `PAYMENT_CANCELLED`→`CANCEL`; `PAYMENT_REFUNDED`/`PAYMENT_PARTIALLY_REFUNDED`→`REFUND`. Operações que falham também são auditadas (`success: false`). Publicação best-effort, Publisher Confirms, routing key `audit.event.published`, credencial via OpenBao. RabbitMQ não entra no `GET /ready` (ADR-019) — coerente com a natureza best-effort da publicação.

Propagado para: `arquitetura/decisoes/ADR-010-comunicacao-http-sincrona-sem-rabbitmq.md` (Decisão consolidada + nota de integração), `dominio/03-business-decisions.md` (BD-14, BD-18 atualizadas), `arquitetura/13-architecture.md` ("Não depende de" atualizado; nova nota de publicação de auditoria em "Eventos internos"), `arquitetura/15-infrastructure.md` (credencial RabbitMQ nos segredos + nova seção "RabbitMQ — Uso Exclusivo para Auditoria"), `contratos/18-event-contracts.md` (cabeçalho consolidado + nova seção "Auditoria — Publicação em `audit.events`"), `produto/visao-do-produto.md` (seções 3 e 9), este roadmap.

Referências: `codepump/codepump/docs/padrao-desenvolvimento.md` (seções 17, 17.3, 18), `organization-service/docs/arquitetura/decisoes/ADR-011-rabbitmq-uso-exclusivo-auditoria.md`, `alert-service/docs/arquitetura/decisoes/ADR-010-rabbitmq-uso-exclusivo-auditoria.md`.

---

### 2026-08-13 — ADR-018/ADR-019: Banco de Dados Exclusivo + Health Check/Readiness Check/Identificação de Build

Adoção de dois padrões organizacionais definidos em `codepump/codepump/docs/padrao-desenvolvimento.md` no mesmo dia (seções 8.2 e 12, 2026-08-13), obrigatórios para todos os serviços já documentados, incluindo `payment-service` (citado nominalmente nas duas).

**Nova ADR — ADR-018** (`arquitetura/decisoes/`): formaliza o banco lógico `payment` como exclusivo deste serviço (já era de fato assim, BD-17) — instância física pode ser compartilhada por economia (ADR-007), banco lógico/schema/tabela nunca.

**Nova ADR — ADR-019** (`arquitetura/decisoes/`): contrato completo de `GET /health` (liveness) e `GET /ready` (readiness) + geração de `build.properties`. Dependências obrigatórias do `/ready`: banco `payment` e `auth-service` (via `GET /health` dele). `Billing Service`, `Person Service`, `Payment Provider`, `Notification Service`, OpenBao e RabbitMQ **não** são obrigatórias — `Notification Service`/OpenBao por reaproveitamento direto de precedentes já registrados (`auth-service` ADR-023, `billing-service` ADR-018 daquele serviço); `Payment Provider` por não ter mecanismo de health-check oficial disponível ainda (Hotspot H01) e pela proibição organizacional de testar disponibilidade com uma transação real; `Billing Service`/`Person Service` por decisão registrada como **novo Hotspot H04** — ambos têm uma chamada síncrona genuinamente bloqueante (BD-11/BD-16), mas restrita a uma fração dos endpoints (criação, e para `Person Service` só o subtipo `PAY`), mesmo cenário de ambiguidade real já identificado por `person-service` (Hotspot H05 daquele serviço) e não coberto explicitamente pela regra organizacional (seção 12.3).

**Nota de conformidade:** confirmado, na mesma ADR-019, que este serviço já está em conformidade com o terceiro padrão organizacional da mesma data (Tarefas Agendadas via `scheduler-service`, `padrao-desenvolvimento.md` seção 13) — `contratos/18-event-contracts.md`, seção "Jobs Internos — Não São Eventos de Domínio", já documentava a ausência de qualquer job periódico interno; nenhuma migração foi necessária.

Propagado para: `dominio/03-business-decisions.md` (BD-17 emendada, referenciando ADR-018/ADR-019), `dominio/01-event-storming-big-picture.md` (novo Hotspot H04), `arquitetura/13-architecture.md` (bullets de banco exclusivo e monitoração; seção "Job Interno" com nota de conformidade), `arquitetura/15-infrastructure.md` (bullet de exclusividade + novas subseções `build.properties` e Health/Readiness Check), `contratos/17-api-contracts.md` (nova seção 8 — Health/Ready/Build — e nova tabela "Resumo de Rotas"), `contratos/18-event-contracts.md` (nota de conformidade com a seção 13), este roadmap.

Referências: `arquitetura/decisoes/ADR-018-banco-dados-exclusivo-por-servico.md`, `arquitetura/decisoes/ADR-019-health-check-readiness-check-build.md`, `codepump/codepump/docs/padrao-desenvolvimento.md` (seções 8.2, 12, 13).

---

### 2026-08-13 — Documentação inicial completa: Visão do Produto a Planejamento (etapas 2 a 8)

O usuário pediu a criação da documentação completa do `payment-service`, fornecendo um documento funcional detalhado (39 seções, cobrindo objetivo, responsabilidades, conceito de Payment, relação com `Billing Service`, identificação por UUID, estrutura do Payment, tipo (RECEIVE/PAY), meio de pagamento, status e transições, idempotência de criação e de webhook, criação, fluxos completos de recebimento e de pagamento, dados do recebedor, dados sensíveis, provedores, webhook, consulta por ID e por cobrança, histórico, tentativas múltiplas, estorno, eventos, comunicação com `Billing Service`, notificações, banco de dados, valores financeiros, autenticação/autorização, logs, correlation ID, auditoria, escopo da primeira versão, exclusões explícitas, dois fluxos completos de ponta a ponta e a regra arquitetural principal) e pediu para usar `padrao-desenvolvimento.md` como base — explicitamente **sem** criar um `Payout Service` separado, reafirmando a separação Order/Billing/Payment/Provider/Person/Notification já estabelecida em `billing-service`.

Escritos, em um único levantamento: `produto/visao-do-produto.md` (14 seções, incluindo a leitura de estorno documentada na seção 11); domínio completo (`01-event-storming-big-picture.md` — 9 fluxos e 3 Hotspots; `02-event-stories.md` — 9 Event Stories; `03-business-decisions.md` — 19 Decisões de Negócio; `04-ubiquitous-language.md`; `05-bounded-contexts.md` — 2 Bounded Contexts, Payment/Auditoria; `06-context-map.md`; `07-domain-services.md` — Idempotência, Transição de Status, Integração com Provedor, Obtenção de Dados do Recebedor; `08-aggregates.md` — 1 agregado (Payment + Histórico), 10 invariantes; `09-domain-state-machines.md` — máquina de 7 estados, transições proibidas explícitas); requisitos completos (`10-functional-requirements.md` — RF-01 a RF-09; `11-non-functional-requirements.md` — RNF-01 a RNF-12; `12-acceptance-criteria.md`); arquitetura completa (`13-architecture.md` — componente único, abstração `PaymentProvider`; `15-infrastructure.md`; 17 ADRs, incluindo ADR-006 — imutabilidade do Payment, sem remoção lógica, desviando do padrão organizacional na direção de mais rigidez — e ADR-016 — estorno somente reativo); contratos (`17-api-contracts.md` — 7 seções, envelope de erro aninhado padrão, sem desvio; `18-event-contracts.md` — eventos internos + comunicação HTTP síncrona com `Billing Service`/`Person Service`/`Payment Provider`); modelo de dados (`19-data-model.md` — 4 tabelas); planejamento (`20-epics.md` — 4 Épicos; `21-user-stories.md` — 8 Histórias, RF-04 incorporada à História de RF-01); e o espelho não técnico (`funcional/documento-funcional.html`).

Diferenças centrais em relação aos demais serviços: (1) é o primeiro serviço cujo agregado principal é **imutável** por definição de negócio — nenhuma edição, nenhuma remoção lógica, uma nova tentativa é sempre um novo registro (ADR-006); (2) reaproveita, sem reinventar, dois contratos já publicados por serviços irmãos — `GET /v1/billings/{id}` e `POST /v1/billings/{id}/payment-events` de `billing-service`, e `GET /v1/persons/{personId}/receiving-accounts` de `person-service` (confirmado por leitura direta daquele serviço antes de assumir o contrato) — reduzindo o número de Hotspots abertos em vez de inventar novos; (3) depende de um provedor de pagamento externo real ainda não escolhido pela empresa, tornando H01/H02 estruturalmente diferentes dos Hotspots de outros serviços — não é ambiguidade de regra de negócio, é decisão de fornecedor pendente.

Três Hotspots ficaram abertos (H01, H02, H03) — nenhum bloqueia o início da Implementação de E1/E4, mas H01/H02 bloqueiam a integração real de E2/E3.

Referências: todos os arquivos em `docs/`, listados acima.
