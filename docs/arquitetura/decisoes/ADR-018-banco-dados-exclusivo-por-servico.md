# ADR-018 — Banco de Dados Exclusivo por Serviço (Adoção do Padrão Organizacional)

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

ADR-007 fixou a topologia de infraestrutura do MVP (PostgreSQL em instância única, sem backup/replicação inicial); ADR-008 fixou o OpenBao como Secrets Manager centralizado. Nenhum dos dois, nem qualquer outro documento deste projeto, formalizava explicitamente uma regra mais básica e anterior a ambos: que o banco de dados deste serviço é **exclusivo** — nunca compartilhado, em nível de schema/tabela, com o banco de nenhum outro serviço da organização. Na prática, `payment-service` sempre operou dessa forma — nenhuma tabela sua (`payments`, `payment_status_history`, `payment_provider_events`, `audit_logs`, `19-data-model.md`) é referenciada por outro serviço, nenhuma `FK` cruza serviços (`billing_id` já é uma referência opaca ao `Billing Service`, sem FK real, BD-17; `personId` sequer é persistido, BD-16) —, mas isso nunca havia sido registrado como decisão própria, só vivido como comportamento implícito, exatamente como já observado em `auth-service` (ADR-022 daquele serviço), `person-service` (ADR-013 daquele serviço) e `billing-service` (ADR-017 daquele serviço), todas da mesma data.

Em 2026-08-13, `codepump/codepump/docs/padrao-desenvolvimento.md` (seção 8.2) formalizou esse princípio como **padrão organizacional obrigatório**, citando `payment-service` nominalmente entre os serviços que já registravam alguma variante de "cada serviço é dono do próprio banco" em sua própria Decisão de Negócio (BD-17) — deixando de ser uma prática implícita repetida caso a caso para se tornar uma regra única, com uma exceção explícita: **múltiplos serviços podem compartilhar a mesma instância física de PostgreSQL por economia de infraestrutura nesta fase de MVP** (coerente com ADR-007 — instância única), mas o **banco de dados lógico** (`CREATE DATABASE`) de cada serviço é sempre próprio, nunca compartilhado.

## Decisão

1. **`payment-service` tem um banco de dados lógico próprio e exclusivo: `payment`** (`CREATE DATABASE payment`, nome fixado pela tabela de referência da seção 8.2 de `padrao-desenvolvimento.md`) — nenhum outro serviço da organização (`auth-service`, `person-service`, `billing-service`, `storage-service`, `notification-service`, `scheduler-service`) lê ou escreve, direta ou indiretamente (nem tabela, nem schema, nem view, nem replicação lógica), nesse banco.
2. **Credencial dedicada:** este serviço se conecta ao banco `payment` com um usuário PostgreSQL próprio, cuja senha é gerida pelo OpenBao (ADR-008) — nunca uma credencial compartilhada com outro serviço, mesmo que o banco `payment` conviva com o banco lógico de outro serviço na mesma instância física.
3. **Compartilhamento permitido apenas na camada física, nunca na lógica:** por custo de infraestrutura nesta fase de MVP (ADR-007), o processo/servidor PostgreSQL que hospeda `payment` pode ser o mesmo processo físico que hospeda o banco lógico de outro serviço — decisão de infraestrutura, não de aplicação. O banco lógico `payment`, seu schema e suas tabelas nunca são acessados por outro serviço, independentemente de estarem ou não na mesma instância física.
4. **Nenhuma `FOREIGN KEY` cruza serviços.** Este serviço já não referencia nenhuma entidade de outro serviço hoje — `payments.billing_id` (referência ao `Billing Service`, BD-01, BD-17) já é um campo opaco (`UUID`, sem `FK` real), e `personId` (consultado em tempo real do `Person Service` para pagamentos `PAY`, BD-16) sequer é persistido — mesmo comportamento de qualquer futura referência a outro serviço. Esta decisão apenas formaliza, como regra permanente, que isso nunca deve mudar.
5. **Nenhuma migração de schema (`golang-migrate`, `padrao-desenvolvimento.md` seção 6) deste serviço referencia, cria índice sobre, ou altera uma tabela de outro serviço** — e vice-versa.
6. **Toda troca de dado com outro serviço acontece via API (síncrona) ou evento (assíncrono), nunca por acesso direto a dado persistido por outro serviço.** Já é o caso hoje: as únicas integrações diretas de `payment-service` com outro serviço são a validação de JWT contra `auth-service` (`GET /v1/auth/public-key`, ADR-001), a consulta e o informe síncronos ao `Billing Service` (BD-11, ES-07), a consulta síncrona ao `Person Service` (BD-16), a publicação de evento ao `Notification Service` (BD-01) e a integração com o `Payment Provider` (BD-13) — nunca um acesso ao banco de nenhum desses serviços.

## Consequências

### Positivas

- Formaliza, como regra explícita e vinculante, um isolamento que este serviço já praticava implicitamente — elimina qualquer ambiguidade para decisões futuras (ex.: uma eventual "consulta agregada" entre `payment-service` e `Billing Service`/`Person Service` nunca deve ser resolvida por `JOIN` direto entre bancos, sempre por chamada de API e agregação em memória).
- Torna explícita a distinção entre "instância física compartilhável" (ADR-007, decisão de custo já tomada) e "banco lógico exclusivo" (esta ADR) — as duas nunca devem ser confundidas.
- Facilita uma futura migração de `payment` para sua própria instância física (quando a instância única deixar de ser suficiente — ver ADR-007, Critérios para reavaliar): por nenhum serviço nunca ter tido acesso direto ao banco de outro, essa migração é puramente de infraestrutura, sem exigir mudança de código de nenhum serviço.

### Negativas

- Nenhuma mudança prática imediata é exigida — este serviço já operava assim. O custo desta ADR é inteiramente de formalização/documentação, não de implementação.
- Reforça uma restrição que precisa ser lembrada em toda decisão futura de modelagem (ex.: se um dia surgir a tentação de uma consulta administrativa cruzando dados de `payment-service` e `Billing Service` diretamente no banco, por conveniência de relatório) — a resposta correta é sempre agregação em memória via chamadas de API, nunca uma exceção pontual a esta regra.

## Critérios para reavaliar

Reavaliar apenas a camada física (não a exclusividade lógica, que nunca é reavaliada) quando a instância física única (ADR-007) deixar de ser suficiente por volumetria, isolamento de performance entre serviços, ou requisito de compliance — nesse caso, migrar `payment` para sua própria instância física é uma mudança de infraestrutura pura.

## Nota de integração

* `arquitetura/15-infrastructure.md` — novo bullet confirmando/cruzando a exclusividade do banco `payment` com esta ADR.
* `dominio/03-business-decisions.md` — BD-17 (Cada Serviço é Dono do Próprio Banco) emendada com referência cruzada a esta ADR e à ADR-019 (ambas originadas do mesmo padrão organizacional de 2026-08-13).
* `arquitetura/13-architecture.md` — componente Payment API / Persistência atualizado.
* `codepump/codepump/docs/padrao-desenvolvimento.md` — seção 8.2, origem deste padrão.
* `roadmap.md`/`roadmap.html` — nova entrada em Concluído.
