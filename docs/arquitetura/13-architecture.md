# Arquitetura — Componentes

> **Desatualizado em 2026-09-07 — o conceito de Contexto foi removido da plataforma.**
>
> O que neste documento descreve Contexto **não vale mais**: a classificação deste serviço no padrão de Contexto — contextual, global ou misto — e tudo que dependa dela. Cada serviço tem um banco, e o endereço dele está na configuração do serviço.
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


> Ponto de partida: os Bounded Contexts de `../dominio/05-bounded-contexts.md` (BC-01, BC-02). Assim como `billing-service`/`person-service`/`storage-service`, este serviço é inteiramente síncrono — todos os BCs vivem, no MVP, dentro de **um único deployável** (Payment API).

---

## Visão Geral

```text
Sistema Consumidor / Billing Service
      │  REST / HTTP / JWT (auth-service)
      ▼
┌───────────────────────────────────────────────────────┐
│                     PAYMENT API                          │
│  Payment (BC-01) · Auditoria (BC-02) — módulos            │
│  internos, chamados em processo, sem mensageria entre     │
│  eles                                                     │
└───┬─────────────────────────────────────┬───────────┬───┘
    │                                     │           │
    ▼                                     ▼           ▼ (HTTP síncrono)
┌───────────────────────────┐   ┌──────────────┐  ┌──────────────────────────┐
│         POSTGRESQL          │   │ Billing       │  │  Person Service /         │
│  payments · payment_status_  │   │ Service       │  │  Notification Service /   │
│  history · payment_provider_ │   │ (consulta +    │  │  Payment Provider          │
│  events · audit_logs          │   │ informe)       │  │  (outbound + webhook       │
└───────────────────────────┘   └──────────────┘  │  inbound)                   │
                                                     └──────────────────────────┘
```

---

## Componentes

### 1. Payment API — mapeia BC-01, BC-02

**Responsabilidade:** único deployável do serviço — autentica/autoriza (via `auth-service`, BD-04), valida, orquestra a integração com o provedor via a abstração `PaymentProvider`, aplica a máquina de status, persiste Payment e histórico, registra auditoria; expõe também o endpoint pelo qual o `Payment Provider` confirma o resultado de uma operação (webhook, inbound).

**Depende de (síncrono, externo, outbound):** `auth-service`, para validar o JWT recebido em toda requisição, e para obter Token de Serviço M2M nas chamadas de saída (chave pública em cache local, mesmo padrão de todos os serviços anteriores); `Billing Service`, para validar a cobrança/valor disponível na criação (BD-11) e para informar o resultado de um pagamento (BD-01, ES-07); `Person Service`, para obter dados de recebimento em pagamentos `PAY` (BD-16); `Notification Service`, para publicar eventos de resultado (BD-01, seção 27 do documento funcional); `Payment Provider`, para enviar a operação na criação (BD-13).

**Depende de (síncrono, inbound):** `Payment Provider` chama este serviço (`POST /v1/payments/webhooks/{provider}`) para confirmar o resultado de uma operação em processamento — não é este serviço que consulta o provedor ativamente após o envio inicial (BD-14, Hotspot H01/H02).

**Não depende de (nesta versão):** nenhum Message Broker para a comunicação de negócio — desvio deliberado do padrão organizacional (BD-14, ADR-010); nenhum segundo provedor implementado (BD-13, Hotspot H01). Este serviço usa RabbitMQ **exclusivamente para publicar auditoria** no exchange `audit.events` (`padrao-desenvolvimento.md` seção 17, `AuditEvent` canônico da `codepump-lib`) — publicador, nunca consumidor; nenhuma fila própria de negócio. O desvio de ADR-010 permanece válido para a comunicação de negócio (que segue HTTP síncrono); ver "Auditoria — Publicação em `audit.events`", abaixo, e `contratos/18-event-contracts.md`.

**Publica (eventos internos, não cruzam processo):** todos os eventos listados em `05-bounded-contexts.md` — consumidos em processo pelo módulo de Auditoria (BC-02).

**Dados próprios:** todas as tabelas de `19-data-model.md` — um único banco PostgreSQL, sem separação física entre os dois BCs. **Banco lógico exclusivo `payment`** (ADR-018, adoção do padrão organizacional `padrao-desenvolvimento.md` seção 8.2) — nenhum outro serviço acessa esse banco, direta ou indiretamente; compartilhamento permitido só na camada física da instância PostgreSQL (ADR-007), nunca no schema/tabela.

**Monitoração:** o Payment API expõe `GET /health` (liveness + identificação de build) e `GET /ready` (readiness, verificando `database` e `auth-service`) — contrato completo em ADR-019 (adoção do padrão organizacional `padrao-desenvolvimento.md` seção 12) e `contratos/17-api-contracts.md`.

---

## Job Interno

Nenhum job interno periódico existe neste serviço nesta versão — diferente de `billing-service` (verificação de vencimento). Toda transição de status é reativa: disparada por uma chamada HTTP de criação ou por um webhook recebido. Não há "verificação de pagamentos pendentes" agendada nesta versão (não pedida pelo documento funcional). Este serviço já está em conformidade com o padrão organizacional de Tarefas Agendadas (`padrao-desenvolvimento.md`, seção 13; ADR-019) sem exigir nenhuma migração — não há goroutine/cron interno a remover, nem endpoint `/internal/*` a criar para o `scheduler-service`.

---

## Por que um único deployável (e não um por Bounded Context)

Este serviço não tem nenhum processamento de longa duração a desacoplar: toda operação (criação, consulta, webhook) é resolvida na mesma requisição HTTP, com uma transação de banco no máximo, mais eventualmente uma ou mais chamadas HTTP síncronas de saída (provedor, `Billing Service`, `Person Service`, `Notification Service`). Separar BC-01/BC-02 em deployáveis distintos hoje adicionaria complexidade operacional sem nenhum ganho correspondente — mesmo racional já aplicado por `billing-service`/`person-service`/`storage-service`.

---

## Eventos internos (não cruzam processo)

Todos os eventos de domínio nomeados em `dominio/02-event-stories.md`/`05-bounded-contexts.md` são publicados em um **despachante de eventos em memória**, dentro do único processo do Payment API, consumidos em processo pelo módulo de Auditoria (BC-02) — mesma decisão de implantação inicial já registrada por `billing-service`/`person-service`/`storage-service` (`18-event-contracts.md`).

**Auditoria — Publicação em `audit.events`:** o despachante em memória continua sendo o mecanismo interno, mas o módulo de Auditoria (BC-02), ao consumi-lo, projeta cada operação financeira relevante (BD-18) em um `AuditEvent` canônico da `codepump-lib` e **publica-o no exchange `audit.events` via RabbitMQ** (`topic`, durable, routing key `audit.event.published`, Publisher Confirms) — este serviço é publicador, nunca consumidor; RabbitMQ existe exclusivamente para auditoria. Publicação best-effort, nunca bloqueia a operação de negócio (Command comitado / webhook processado antes da tentativa de publicação). Mesmo padrão de `organization-service` (ADR-011) e `alert-service` (ADR-010). Contrato completo em `contratos/18-event-contracts.md`; conexão/credencial em `arquitetura/15-infrastructure.md`.

---

## Abstração `PaymentProvider`

Camada de infraestrutura (`internal/infrastructure/provider/`, `padrao-desenvolvimento.md` seção 2) que isola o domínio do contrato específico de cada provedor concreto (BD-13). Nesta versão, uma única implementação concreta (`ProviderA`\*, Hotspot H01) — a interface já está desenhada para múltiplas implementações, escolhidas por configuração:

```text
internal/domain/payment/       # regras de negócio — nunca importa detalhe de provedor
internal/infrastructure/provider/
  provider.go                  # interface PaymentProvider
  provider_a.go                # implementação concreta (nome real pendente, H01)
```

---

## Comunicação HTTP Outbound (sem broker, ADR-010)

A comunicação com `Billing Service` (consulta + informe), `Person Service` (consulta), `Notification Service` (publicação de evento) e `Payment Provider` (envio da operação) acontece via chamada HTTP síncrona, **fora** da transação de banco que originou a mudança de status — se essa chamada falhar, o Payment já está persistido corretamente; a notificação/aviso fica sujeita a retry por fora do fluxo principal (mecanismo exato de retry não especificado nesta versão, mesma limitação já registrada por `billing-service`).

---

## Pontos Abertos

* **Provedor real** (Hotspot H01) — o desenho da implementação concreta (`ProviderA`) pode mudar integralmente quando o provedor real for escolhido.
* **Mecanismo de autenticidade do webhook** (Hotspot H02) — depende diretamente de H01.
* **Endpoint de cancelamento** (`POST /v1/payments/{id}/cancel`\*) — inferido, não literal no documento funcional (ver `12-acceptance-criteria.md`, Valores Assumidos).

---

## Evolução

* Introduzir RabbitMQ quando a necessidade de desacoplamento entre `Payment Service` e `Billing Service`/`Person Service`/`Notification Service`/provedor for real (BD-14, ADR-010) — não antecipar.
* Suportar múltiplos provedores simultâneos, com escolha por regra de negócio, quando houver necessidade real (BD-13, seção 36 do documento funcional).
* Implementar `POST /v1/payments/{id}/refund` quando o Hotspot H03 for resolvido.

---

## Classificação no padrão de Contexto (§28)

**Este serviço é contextual por inteiro** (ADR-024): `payments`, `payment_status_history`, `payment_provider_events` e `audit_logs` vivem no banco do Contexto.

**Ponto aberto:** o webhook do provedor não chega com o `USER JWT` do titular. O Contexto precisa ser resolvido a partir da própria transação — preferencialmente por uma referência que carregue o Contexto e volte no webhook (ADR-024). Enquanto não estiver fechado, o webhook não opera.

A origem do banco por operação é a resolução, nunca a configuração: nenhum repositório guarda pool próprio, nenhum conhece a associação `Contexto → banco`, e não existe Contexto padrão nem banco de fallback (§28.8). Cache, concorrência e ciclo de vida de pool são da `codepump-lib` — se aparecer esse código aqui, está errado por definição.

Ver a ADR de adoção deste serviço e `codepump/docs/padrao-desenvolvimento.md` §28.
