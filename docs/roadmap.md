# Roadmap do Projeto — payment-service

> Etapas referem-se às seções de `padrao-desenvolvimento.html` (codepump).
> Status possíveis: `Pendente` · `Em andamento` · `Bloqueado` · `Feito`
> No companheiro visual (`roadmap.html`), cada item aparece como: 🟢 Feito · 🟡 Incompleto · 🔵 Sem dependências pendentes, pronto para começar · ⚪ Bloqueado por dependência

**Última atualização:** 2026-08-13

---

## Próximo Passo

**Toda a documentação inicial (etapas 2 a 8) foi escrita em um único levantamento**, a partir do documento funcional fornecido pelo usuário (2026-08-13) e da adoção direta do padrão organizacional (`padrao-desenvolvimento.md`) para tudo que já estava fixado (stack Go, autenticação delegada a `auth-service`, OpenBao, logs, padrão de resposta de API, versionamento, envelope de erro) — mesmo perfil de `billing-service`: nenhum Hotspot de infraestrutura/autenticação precisou ser aberto.

Este serviço tem duas particularidades que o distinguem de todos os demais já documentados: (1) diferente de `billing-service` (que representa a obrigação financeira e desvia do padrão de mensageria por HTTP síncrono), `payment-service` executa a movimentação financeira real — é o único serviço com um agregado explicitamente **imutável** após a criação (`Payment` nunca é editado nem removido, ADR-006 — sem análogo de "remoção lógica" nenhum, desviando também desse padrão organizacional, mas na direção de mais rigidez, não menos); (2) depende de um `Payment Provider` externo cujo nome real ainda não foi escolhido pela empresa — isso está na raiz de dois dos três Hotspots abertos (H01, H02).

Com Domínio, Requisitos, Arquitetura, Contratos, Modelo de Dados e Planejamento completos, `Implementação/Código` (etapa 9) tem todas as suas dependências satisfeitas e pode começar — desde que a integração com o `Payment Provider` (E2, `20-epics.md`) seja implementada atrás da abstração `PaymentProvider` (BD-13, ADR-015), isolando o maior risco de retrabalho do plano.

Referência: `dominio/01-event-storming-big-picture.md` (Hotspots), `planejamento/21-user-stories.md`

---

## Status por Etapa

| # | Etapa | Status |
|---|-------|--------|
| 2 | Descoberta do Negócio | Feito |
| 3 | Definição do Domínio | Feito *(Bounded Contexts, Context Map, Entidades, Value Objects, Agregados, Serviços de Domínio, Eventos, Ciclos de Vida — `01-event-storming-big-picture.md` a `09-domain-state-machines.md`; 19 Decisões de Negócio, 9 Event Stories)* |
| 4 | Requisitos | Feito *(9 Funcionais, 12 Não Funcionais e Critérios de Aceite — `10-functional-requirements.md` a `12-acceptance-criteria.md`)* |
| 5 | Arquitetura | Feito *(Componentes, Infraestrutura, Autenticação/Autorização, 17 ADRs — `13-architecture.md`, `15-infrastructure.md`, `arquitetura/decisoes/`)* |
| 6 | Contratos | Feito *(APIs — `17-api-contracts.md`, 7 seções; eventos internos + comunicação HTTP síncrona com `Billing Service`/`Person Service`/`Payment Provider` — `18-event-contracts.md`, sem Message Broker, ADR-010)* |
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

Nenhum dos três bloqueia o início da etapa de Implementação para E1 (Payment) e E4 (Auditoria); **H01/H02 bloqueiam de fato a integração real do E2** (Confirmação do Provedor) e, por consequência de runtime, do E3 (Integração com Billing Service) — mitigado implementando E2 atrás da abstração `PaymentProvider` (BD-13, ADR-015) desde o início, para que a escolha real do provedor não exija redesenho do domínio.

---

## Concluído

### 2026-08-13 — Documentação inicial completa: Visão do Produto a Planejamento (etapas 2 a 8)

O usuário pediu a criação da documentação completa do `payment-service`, fornecendo um documento funcional detalhado (39 seções, cobrindo objetivo, responsabilidades, conceito de Payment, relação com `Billing Service`, identificação por UUID, estrutura do Payment, tipo (RECEIVE/PAY), meio de pagamento, status e transições, idempotência de criação e de webhook, criação, fluxos completos de recebimento e de pagamento, dados do recebedor, dados sensíveis, provedores, webhook, consulta por ID e por cobrança, histórico, tentativas múltiplas, estorno, eventos, comunicação com `Billing Service`, notificações, banco de dados, valores financeiros, autenticação/autorização, logs, correlation ID, auditoria, escopo da primeira versão, exclusões explícitas, dois fluxos completos de ponta a ponta e a regra arquitetural principal) e pediu para usar `padrao-desenvolvimento.md` como base — explicitamente **sem** criar um `Payout Service` separado, reafirmando a separação Order/Billing/Payment/Provider/Person/Notification já estabelecida em `billing-service`.

Escritos, em um único levantamento: `produto/visao-do-produto.md` (14 seções, incluindo a leitura de estorno documentada na seção 11); domínio completo (`01-event-storming-big-picture.md` — 9 fluxos e 3 Hotspots; `02-event-stories.md` — 9 Event Stories; `03-business-decisions.md` — 19 Decisões de Negócio; `04-ubiquitous-language.md`; `05-bounded-contexts.md` — 2 Bounded Contexts, Payment/Auditoria; `06-context-map.md`; `07-domain-services.md` — Idempotência, Transição de Status, Integração com Provedor, Obtenção de Dados do Recebedor; `08-aggregates.md` — 1 agregado (Payment + Histórico), 10 invariantes; `09-domain-state-machines.md` — máquina de 7 estados, transições proibidas explícitas); requisitos completos (`10-functional-requirements.md` — RF-01 a RF-09; `11-non-functional-requirements.md` — RNF-01 a RNF-12; `12-acceptance-criteria.md`); arquitetura completa (`13-architecture.md` — componente único, abstração `PaymentProvider`; `15-infrastructure.md`; 17 ADRs, incluindo ADR-006 — imutabilidade do Payment, sem remoção lógica, desviando do padrão organizacional na direção de mais rigidez — e ADR-016 — estorno somente reativo); contratos (`17-api-contracts.md` — 7 seções, envelope de erro aninhado padrão, sem desvio; `18-event-contracts.md` — eventos internos + comunicação HTTP síncrona com `Billing Service`/`Person Service`/`Payment Provider`); modelo de dados (`19-data-model.md` — 4 tabelas); planejamento (`20-epics.md` — 4 Épicos; `21-user-stories.md` — 8 Histórias, RF-04 incorporada à História de RF-01); e o espelho não técnico (`funcional/documento-funcional.html`).

Diferenças centrais em relação aos demais serviços: (1) é o primeiro serviço cujo agregado principal é **imutável** por definição de negócio — nenhuma edição, nenhuma remoção lógica, uma nova tentativa é sempre um novo registro (ADR-006); (2) reaproveita, sem reinventar, dois contratos já publicados por serviços irmãos — `GET /v1/billings/{id}` e `POST /v1/billings/{id}/payment-events` de `billing-service`, e `GET /v1/persons/{personId}/receiving-accounts` de `person-service` (confirmado por leitura direta daquele serviço antes de assumir o contrato) — reduzindo o número de Hotspots abertos em vez de inventar novos; (3) depende de um provedor de pagamento externo real ainda não escolhido pela empresa, tornando H01/H02 estruturalmente diferentes dos Hotspots de outros serviços — não é ambiguidade de regra de negócio, é decisão de fornecedor pendente.

Três Hotspots ficaram abertos (H01, H02, H03) — nenhum bloqueia o início da Implementação de E1/E4, mas H01/H02 bloqueiam a integração real de E2/E3.

Referências: todos os arquivos em `docs/`, listados acima.
