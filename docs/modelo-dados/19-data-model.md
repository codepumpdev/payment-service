# Modelo de Dados — Tabelas

> **Desatualizado em 2026-09-07 — o conceito de Contexto foi removido da plataforma.**
>
> O que neste documento descreve Contexto **não vale mais**: a separação entre tabelas do banco global e tabelas do banco de Contexto. Todas vivem no mesmo banco do serviço.
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


> Traduz as Entidades de `../dominio/05-bounded-contexts.md` (BC-01, BC-02) em tabelas PostgreSQL (ADR-002/ADR-003), incorporando as regras já fixadas em `../dominio/03-business-decisions.md` (BDs). Três tabelas explicitamente listadas pelo documento funcional fornecido pelo usuário (seção 28: `payments`, `payment_status_history`, `payment_provider_events`), mais `audit_logs` (BD-18 — necessária, mas não citada por nome naquela lista, mesmo padrão de `billing-service`/`person-service`/`storage-service`, que também acrescentaram `audit_logs` além do que a lista inicial do usuário continha).
>
> Tipos usam sintaxe PostgreSQL. `UUID` é gerado pela aplicação. Valores financeiros em `NUMERIC` (ADR-014). Onde o domínio já modelado não fixa um detalhe de schema, este documento resolve de forma simples, marcado com **\*** e listado em "Pontos Abertos".

---

## `payments` (Payment) — BC-01

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `UUID` PK | Gerado pela aplicação (BD-03) |
| `type` | `VARCHAR(10)` NOT NULL, CHECK IN (`'RECEIVE'`, `'PAY'`) | Imutável após criação (BD-02) |
| `billing_id` | `UUID` NOT NULL | Referência opaca a `Billing Service` — sem FK cruzando serviços (BD-17) |
| `amount` | `NUMERIC(14,2)` NOT NULL | Valor da operação — imutável após a criação (diferente de `billing-service`, aqui não há `paidAmount`/`remainingAmount`: pagamento parcial de uma cobrança é modelado como múltiplos Payments, BD-12) |
| `currency` | `VARCHAR(3)` NOT NULL DEFAULT `'BRL'`, CHECK IN (`'BRL'`) | BD-05 — só `BRL` implementado |
| `method` | `VARCHAR(20)` NOT NULL, CHECK IN (`'PIX'`) | BD-06 — só `PIX` implementado nesta versão (catálogo completo reservado no vocabulário, não no `CHECK`) |
| `status` | `VARCHAR(20)` NOT NULL DEFAULT `'PENDING'`, CHECK IN (`'PENDING'`, `'PROCESSING'`, `'APPROVED'`, `'REJECTED'`, `'CANCELLED'`, `'REFUNDED'`, `'PARTIALLY_REFUNDED'`) | Máquina 1 (`09-domain-state-machines.md`) |
| `provider` | `VARCHAR(50)` NULL | Preenchido quando o envio ao provedor é aceito (`PROCESSING`); nome real pendente (Hotspot H01) |
| `provider_payment_id` | `VARCHAR(100)` NULL | Idem — preenchido no máximo uma vez (`08-aggregates.md`, invariante 5) |
| `idempotency_key` | `VARCHAR(150)` NOT NULL | Único em conjunto com `application` (BD-09) |
| `application` | `VARCHAR(100)` NOT NULL | Aplicação chamadora que criou o Payment — usada no escopo de `idempotency_key` |
| `created_at` | `TIMESTAMPTZ` NOT NULL DEFAULT `now()` | — |
| `updated_at` | `TIMESTAMPTZ` NOT NULL DEFAULT `now()` | Atualizado a cada transição de status |
| `owner_user_id` | `UUID` NULL | Titular do Payment (ADR-022/BD-21) — referência **opaca** ao usuário do `auth-service` (o **`sub` do `USER JWT`** recebido no header `X-User`, seção 9.4; padrão §8.2, sem FK cruzando serviços). Usado para **contar registros por usuário** (limite de plano) e **escopar a retenção** por usuário (upgrade). **Não** é dado financeiro de destino (BD-16 preservada — nenhum CPF/chave Pix/conta é gravado; só o identificador de escopo de plano). `NULL` para Payments criados fora de contexto de usuário (sistema-a-sistema, só `SERVICE JWT`, ex.: `PAY` disparado por `Billing Service`), que ficam fora de recurso/limite/retenção. Índice `payments(owner_user_id)` para a contagem |
| `purge_at` | `TIMESTAMPTZ` NULL | Data de expurgo da retenção temporária do plano `FREE` (ADR-022/BD-21; seção 26.6 do padrão). `purge_at = created_at + retentionDays` na criação sob titular `FREE`; `NULL` quando não há retenção (`PRO`/`MAX`, ou sem titular). Fica **somente** nesta entidade raiz `payments` — `payment_status_history`/`payment_provider_events` não têm `purge_at`; são removidos junto com o Payment pelo `POST /internal/purge` (ADR-022). Índice parcial `payments(purge_at) WHERE purge_at IS NOT NULL` para o expurgo. *(No MVP fica inerte: `FREE` não permite o recurso `PAYMENT`, logo nenhum Payment `FREE` é criado — ADR-022.)* |

```sql
CREATE UNIQUE INDEX payments_idempotency_key_per_application
  ON payments (idempotency_key, application);

CREATE UNIQUE INDEX payments_provider_payment_id
  ON payments (provider, provider_payment_id)
  WHERE provider_payment_id IS NOT NULL;
```

Unicidade de `idempotencyKey` no contexto da Aplicação, não global (BD-09); unicidade de `provider + provider_payment_id`, quando preenchido, para permitir localizar um Payment a partir de um webhook sem ambiguidade (seção 28 do documento funcional, textual).

**Índices adicionais:** `payments(billing_id)`, `payments(status)`, `payments(created_at)` — necessários para RF-03/RF-06 (`17-api-contracts.md`, `01-event-storming-big-picture.md`).

---

## `payment_status_history` (Histórico de Status) — BC-01

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `UUID` PK | — |
| `payment_id` | `UUID` NOT NULL, FK → `payments(id)` ON DELETE RESTRICT | `RESTRICT` defensivo — não há endpoint de remoção física de Payment (ADR-006) |
| `from_status` | `VARCHAR(20)` NULL, CHECK IN (`'PENDING'`, `'PROCESSING'`, `'APPROVED'`, `'REJECTED'`, `'CANCELLED'`, `'REFUNDED'`, `'PARTIALLY_REFUNDED'`) | `NULL` só na primeira linha (criação) |
| `to_status` | `VARCHAR(20)` NOT NULL, CHECK IN (`'PENDING'`, `'PROCESSING'`, `'APPROVED'`, `'REJECTED'`, `'CANCELLED'`, `'REFUNDED'`, `'PARTIALLY_REFUNDED'`) | — |
| `reason` | `VARCHAR(255)` NULL | Opcional — ex.: motivo de cancelamento |
| `provider_event_id` | `VARCHAR(150)` NULL | Preenchido quando a transição foi originada por um webhook (ES-06) |
| `created_at` | `TIMESTAMPTZ` NOT NULL DEFAULT `now()` | — |

Append-only por convenção de aplicação — nenhuma coluna `updated_at`, nenhum endpoint de alteração/remoção (ver `padrao-desenvolvimento.md`, seção 6 — nota de simplificação desta rodada: sem `created_by` explícito nesta versão, diferente de `billing-service`, pois toda transição deste serviço é originada por sistema (criação via Sistema Consumidor já registrada em `application`, webhook já registrado em `provider_event_id`) — nenhum ator humano aplica transição diretamente).

**Índices adicionais:** `payment_status_history(payment_id, created_at)` — monta o histórico ordenado de um Payment (RF-08, seção 7 de `17-api-contracts.md`).

---

## `payment_provider_events` (Evento de Provedor) — BC-01

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `UUID` PK | — |
| `provider` | `VARCHAR(50)` NOT NULL | Nome do provedor que originou o webhook (Hotspot H01) |
| `provider_event_id` | `VARCHAR(150)` NOT NULL | Identificador único do evento, atribuído pelo provedor (BD-10) |
| `payment_id` | `UUID` NULL, FK → `payments(id)` ON DELETE RESTRICT | `NULL` quando o `providerPaymentId` recebido não corresponde a nenhum Payment conhecido (registrado mesmo assim, para diagnóstico) |
| `event_type` | `VARCHAR(50)` NOT NULL | Valor bruto recebido do provedor — não normalizado ao vocabulário interno nesta coluna (a tradução acontece na aplicação, BD-13) |
| `received_at` | `TIMESTAMPTZ` NOT NULL DEFAULT `now()` | — |
| `processed_at` | `TIMESTAMPTZ` NULL | Preenchido quando o processamento (aplicação da transição) é concluído |
| `status` | `VARCHAR(20)` NOT NULL DEFAULT `'RECEIVED'`, CHECK IN (`'RECEIVED'`, `'PROCESSED'`, `'IGNORED'`, `'INVALID'`) | `IGNORED` = evento já processado antes (idempotência); `INVALID` = falha de validação de autenticidade |

```sql
CREATE UNIQUE INDEX payment_provider_events_unique_event
  ON payment_provider_events (provider, provider_event_id);
```

Garante a idempotência de webhook (BD-10) — a segunda tentativa de inserir o mesmo par `(provider, provider_event_id)` falha na constraint, sinalizando à aplicação que o evento já foi recebido.

**Índices adicionais:** `payment_provider_events(payment_id)`, `payment_provider_events(received_at)`.

---

## `audit_logs` (Registro de Auditoria) — BC-02

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `UUID` PK | — |
| `payment_id` | `UUID` NOT NULL, FK → `payments(id)` ON DELETE RESTRICT | Referência direta — mesmo padrão de `billing-service` (`audit_logs.billing_id`) |
| `billing_id` | `UUID` NOT NULL | Referência opaca, denormalizada para consulta direta sem join a `payments` (mesmo padrão de conveniência já aceito em outros serviços) |
| `operation` | `VARCHAR(30)` NOT NULL, CHECK IN (`'PAYMENT_CREATED'`, `'PAYMENT_APPROVED'`, `'PAYMENT_REJECTED'`, `'PAYMENT_CANCELLED'`, `'PAYMENT_REFUNDED'`, `'PAYMENT_PARTIALLY_REFUNDED'`) | Catálogo fechado de BD-18 *(`PAYMENT_PARTIALLY_REFUNDED` adicionado em 2026-08-13, verificação — sem ele, uma transição `APPROVED → PARTIALLY_REFUNDED` não teria `operation` válida para RF-09)* |
| `application` | `VARCHAR(100)` NOT NULL | Aplicação chamadora, ou `SYSTEM` para transições originadas por webhook |
| `actor` | `VARCHAR(100)` NOT NULL | Subject do JWT, ou `SYSTEM` |
| `created_at` | `TIMESTAMPTZ` NOT NULL DEFAULT `now()` | — |

Nunca grava chave Pix, conta bancária, CVV ou qualquer dado financeiro sensível (BD-15, BD-18).

**Índices adicionais:** `audit_logs(payment_id, created_at)`, `audit_logs(billing_id, created_at)`.

---

## Relacionamentos (visão geral)

```text
payments (1) ──< (0..N) payment_status_history
payments (1) ──< (0..N) payment_provider_events
payments (1) ──< (0..N) audit_logs
```

Nenhuma tabela tem FK para fora deste banco — `billing_id` é referência opaca a `Billing Service`, sem FK cruzando serviços (BD-17); `personId` (usado só na chamada síncrona ao `Person Service`, ES-04) nunca é persistido em nenhuma tabela deste serviço (BD-16, RNF-12).

---

## Pontos Abertos

* **Nenhuma coluna de dado financeiro de destino** (chave Pix, conta bancária, cartão) existe em nenhuma tabela — decisão deliberada (BD-16, RNF-12), não uma omissão a revisar.
* **Formato de `provider_payment_id`/`event_type`** — dependem do provedor real (Hotspot H01).
* **Estorno** — nenhuma coluna específica para rastrear valor estornado além do `status`/histórico; se `POST /v1/payments/{id}/refund` for implementado no futuro (Hotspot H03), pode exigir uma tabela própria (`payment_refunds`) se estornos parciais múltiplos precisarem ser somados.

---

## Evolução

* **Migrações de schema:** `golang-migrate`, ordem sugerida por dependência de FK:
  ```text
  000001_create_payments
  000002_create_payment_status_history
  000003_create_payment_provider_events
  000004_create_audit_logs
  000005_add_owner_user_id_and_purge_at_to_payments   -- ADR-022/BD-21: colunas + índices payments(owner_user_id) e payments(purge_at) WHERE purge_at IS NOT NULL
  ```
* Se múltiplos meios de pagamento além de `PIX` forem suportados no futuro (BD-06, Evolução), `method` deixa de ter `CHECK` fixo em `'PIX'` — mudança aditiva simples.
* Se múltiplas moedas forem suportadas no futuro (BD-05, Evolução), `currency` deixa de ter `CHECK` fixo em `'BRL'` — mudança aditiva simples.
* Se um segundo provedor for implementado (BD-13, Evolução), nenhuma mudança de schema é necessária — `provider` já é um campo livre, não um `CHECK` fechado.

---

## Origem do banco: contextual (§28, ADR-024)

`payments`, `payment_status_history`, `payment_provider_events` e `audit_logs` vivem no **banco do Contexto**, resolvido pelo `ContextResolver` a partir do claim `context`. Não há tabela global neste serviço.

**Ponto aberto — webhook:** o retorno do provedor não traz o `USER JWT` do titular, e não se pode varrer bancos procurando a transação. O Contexto precisa vir da própria referência enviada ao provedor (opção preferida) ou de um índice global `transação → Contexto`, que tornaria o serviço misto (ADR-024).
