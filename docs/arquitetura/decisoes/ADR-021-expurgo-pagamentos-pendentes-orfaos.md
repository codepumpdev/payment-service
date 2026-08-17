# ADR-021 — Expurgo de Pagamentos `PENDING` Órfãos (`POST /internal/purge`)

- **Status:** Aceita
- **Data:** 2026-08-14

## Contexto

Um Pagamento nasce `PENDING` (RF-01) associado a uma Cobrança do `billing-service` pelo `billingId`. Se a Cobrança correspondente deixa de existir — por exemplo, foi expurgada por retenção (`billing-service` ADR-021) ou nunca chegou a ser criada por uma falha de coordenação entre serviços — o Pagamento `PENDING` fica **órfão**: aponta para uma fatura que não existe mais e nunca sairá de `PENDING`, porque o fluxo que o resolveria (confirmação/rejeição do provedor, RF-02/RF-03) está atrelado a uma Cobrança inexistente. O usuário definiu um **expurgo** desses pagamentos `PENDING` órfãos, executado periodicamente pelo `scheduler-service` — endpoint padronizado `POST /internal/purge` (`padrao-desenvolvimento.md`, seção 5).

Esta ADR é a **exceção explícita** à ADR-006 (`payment-imutavel-sem-remocao`): um Pagamento é imutável e nunca removido pela API de negócio. A ADR-006 continua valendo integralmente para toda operação exposta ao cliente. O expurgo por retenção não é operação de negócio; é manutenção interna disparada por máquina, prevista na seção 5 do padrão. Diferente do expurgo do `billing-service` (que usa idade), o critério aqui é **relacional** (a fatura associada não existe), o que exige verificação M2M contra o `billing-service`.

**Segundo motivo de expurgo — retenção `FREE` (ADR-022/BD-21):** o `POST /internal/purge` desta ADR tem um **segundo motivo** de expurgo — a **retenção `FREE`** do padrão de Planos (seção 26.8): além dos órfãos-`PENDING` descritos aqui, a mesma operação remove os `payments` com `purge_at <= now()` e seus relacionados. Esse segundo critério é **temporal** (`purge_at`), **não** relacional — **não** consulta o `billing-service` e independe do status. Os dois motivos coexistem na mesma execução/endpoint (seção 26.8: nunca criar um endpoint separado). A resposta inclui `retentionPurged`; `paymentsPurged` soma os dois. Tudo o que esta ADR fixa sobre o motivo órfão-`PENDING` (fail-safe, verificação M2M, auditoria preservada, idempotência) permanece **inalterado**. Ver ADR-022, BD-21, `contratos/17-api-contracts.md` (seções 9 e 10) e `19-data-model.md` (`payments.purge_at`).

## Decisão

### 1. `POST /internal/purge` — operação interna, disparada por `scheduler-service`

- **Endpoint:** `POST /internal/purge` — fora do prefixo `/v1` (operação interna), **nunca exposto externamente pelo Nginx** (rota `/internal/*`, seção 14.3 do padrão). Nome **exatamente** `purge`, idêntico entre todos os serviços (padrão, seção 5).
- **Autenticação:** JWT M2M, perfil **`SCHEDULER`** (nunca `ADMIN` — seção 9.1 do padrão), validado no backend.

### 2. Regra de expurgo — exclusão física de `PENDING` órfãos, com verificação M2M

Um Pagamento é elegível **somente** se atender **todas** as condições:

```text
status = PENDING
  AND  a Cobrança referenciada por billingId NÃO existe em billing-service (verificado via M2M)
  AND  createdAt < (data atual − minPendingAge)   (salvaguarda anti-corrida, ver abaixo)
```

- **Somente `status = PENDING`** — `APPROVED`, `REJECTED`, `CANCELLED` e `REFUNDED` são registros financeiros consolidados e **nunca** são expurgados por esta regra, existindo ou não a fatura. Um pagamento já aprovado permanece como prova contábil independentemente da fatura.
- **Verificação M2M obrigatória contra `billing-service`** — para cada candidato `PENDING`, consultar o `billing-service` (chamada interna M2M, perfil `SCHEDULER`/serviço) se a Cobrança `billingId` existe. Só é expurgado quando o `billing-service` responde **conclusivamente** que a Cobrança **não** existe (ex.: `404`).
- **Resiliência — na dúvida, não expurga (fail-safe):** se o `billing-service` estiver **indisponível**, responder com erro (5xx), timeout, ou de forma **inconclusiva**, o Pagamento **não** é expurgado nesta execução. Nunca se apaga um Pagamento sem confirmação positiva de que a fatura não existe. O expurgo é adiado para a próxima execução (idempotente) — a ausência de fatura é uma condição permanente, não perde-se nada em esperar.
- **Salvaguarda anti-corrida (`minPendingAge`, assumida\*):** um Pagamento `PENDING` recém-criado pode legitimamente referenciar uma Cobrança ainda em criação (janela de coordenação entre serviços). Para não expurgar um pagamento em pleno fluxo, só são considerados candidatos os `PENDING` com `createdAt` anterior a `minPendingAge` (padrão assumido **24h**, configurável `payment.purge.minPendingAgeHours`). Valor sem base empírica ainda — **Hotspot\***, reavaliar conforme a janela real de coordenação `billing`↔`payment`.

O expurgo é `DELETE` físico do Pagamento; **nunca** toca em dado financeiro sensível de terceiros por não o armazenar (BD/ADR de não-replicação — número de cartão, chave Pix, conta bancária não vivem neste serviço; são resolvidos pelo provedor/`person-service` em tempo de execução).

### 3. Auditoria preservada

O expurgo **nunca** remove registros de auditoria relacionados ao pagamento — a auditoria vive em `audit-service`, com política de retenção própria (seção 17 do padrão). Expurgar um Pagamento órfão não apaga o histórico de que ele existiu.

### 4. Auditoria da própria operação (destrutiva)

Registrada com o `AuditEvent` canônico (seção 17 do padrão): `action` `DELETE`, `resource` `PAYMENT`, `data` mínimo — `operation: "PAYMENT_PURGE"`, `paymentsPurged`, `executedBy: "scheduler-service"`, `correlationId`, `timestamp`. **Nunca** conteúdo do pagamento nem qualquer dado financeiro.

### 5. Idempotência e resposta

Idempotente — reexecução sem elegíveis retorna `paymentsPurged: 0`. Candidatos não confirmados como órfãos (billing indisponível) simplesmente não são expurgados e reaparecem como candidatos na próxima execução. Resposta é um resumo, **sem** conteúdo de pagamento:

```json
{
  "status": "SUCCESS",
  "executedAt": "2026-08-14T03:00:00-03:00",
  "candidatesEvaluated": 340,
  "billingUnavailableSkipped": 5,
  "paymentsPurged": 22
}
```

`billingUnavailableSkipped` expõe explicitamente quantos candidatos foram **poupados** por não se ter conseguido confirmar a ausência da fatura — sinal operacional de que o `billing-service` esteve indisponível durante a execução.

### 6. Configuração

`payment.purge.minPendingAgeHours` (padrão **24**) — configurável sem mudança de código, refletido em `GET /props` (`limits`, seção 16 do padrão), administrável pela tela `/admin/config` (ADR-020). Nunca expor secret pela configuração ou pela UI.

## Consequências

### Positivas

- Pagamentos `PENDING` órfãos deixam de acumular sem resolução na tabela `payment`.
- Fecha o ciclo com o expurgo de faturas do `billing-service` (ADR-021 daquele serviço): quando uma fatura vencida é expurgada lá, um eventual pagamento `PENDING` que a referenciava se torna órfão e passa a ser elegível aqui — sem acoplamento síncrono entre os dois expurgos (cada um roda por sua própria Scheduled Task).
- A regra fail-safe garante que uma indisponibilidade do `billing-service` **nunca** cause exclusão indevida.

### Negativas / Hotspots

- **Exceção à ADR-006** (imutável, sem remoção) — primeira exclusão física de Pagamento. Aceita como política de retenção (seção 5 do padrão), restrita a `PENDING` órfão; não abre precedente para remover pagamentos consolidados.
- **Dependência de disponibilidade do `billing-service`** para efetivar o expurgo — por design (fail-safe). Se `billing-service` ficar longos períodos indisponível, órfãos permanecem até a próxima execução bem-sucedida; aceitável (condição permanente, sem urgência).
- **`minPendingAge` assumido (Hotspot\*)** — 24h é ponto de partida sem base empírica; reavaliar conforme a janela real de coordenação `billing`↔`payment`.

## Critérios para reavaliar

- Ajustar `minPendingAgeHours` conforme a janela real de coordenação entre criação de Cobrança e criação de Pagamento.
- Se o volume de candidatos tornar a verificação M2M por item cara, avaliar uma verificação em lote (`billing-service` expor uma consulta "quais destes `billingId` existem?") em vez de uma chamada por pagamento — hoje assume-se verificação individual\*.

## Nota de integração

* `requisitos/10-functional-requirements.md` — novo **RF-10** (expurgo de pagamentos `PENDING` órfãos).
* `dominio/03-business-decisions.md` — nova **BD-20** (expurgo físico de `PENDING` órfão; verificação M2M obrigatória; fail-safe se billing indisponível; salvaguarda `minPendingAge`; auditoria preservada; operação destrutiva auditada e idempotente).
* `dominio/08-aggregates.md` — Pagamento: nota de que um `PENDING` órfão (fatura inexistente) além de `minPendingAge` é **removido fisicamente** (exceção de retenção); demais status nunca.
* `dominio/09-domain-state-machines.md` — Pagamento: um `PENDING` órfão é **expurgado** (removido), não uma transição de estado.
* `dominio/01-event-storming-big-picture.md`, `02-event-stories.md`, `07-domain-services.md` — novo fluxo/ES de expurgo; serviço de domínio "Expurgador de Pagamentos Órfãos".
* `dominio/06-context-map.md` — `scheduler-service` dispara `POST /internal/purge`; `billing-service` é consultado (M2M) para verificar existência da Cobrança; `audit-service` recebe o `AuditEvent`.
* `contratos/17-api-contracts.md` — nova seção 9 com o contrato de `POST /internal/purge`; nova linha na tabela "Resumo de Rotas".
* `arquitetura/decisoes/ADR-020-interface-web-configuracao.md` — nova propriedade configurável `payment.purge.minPendingAgeHours`.
* `arquitetura/decisoes/ADR-006-payment-imutavel-sem-remocao.md` — nota de que o expurgo por retenção de `PENDING` órfão (ADR-021) é a exceção da seção 5 do padrão.
* `scheduler-service` (`dominio/03-business-decisions.md`, `dominio/01-event-storming-big-picture.md`, `arquitetura/13-architecture.md`) — nova Scheduled Task `payment-orphan-purge` → `payment-service` `POST /internal/purge`.
* `codepump/codepump/docs/padrao-desenvolvimento.md` — seção 5 (exceção de expurgo / endpoint padronizado), seção 13 (scheduler), seção 17 (auditoria), seção 9.1 (perfil `SCHEDULER`), seção 16/23 (configuração/`/props`/`/admin/config`).
