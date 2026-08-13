# Arquitetura — Componentes

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

**Não depende de (nesta versão):** nenhum Message Broker — desvio deliberado do padrão organizacional (BD-14, ADR-010); nenhum segundo provedor implementado (BD-13, Hotspot H01).

**Publica (eventos internos, não cruzam processo):** todos os eventos listados em `05-bounded-contexts.md` — consumidos em processo pelo módulo de Auditoria (BC-02).

**Dados próprios:** todas as tabelas de `19-data-model.md` — um único banco PostgreSQL, sem separação física entre os dois BCs.

---

## Job Interno

Nenhum job interno periódico existe neste serviço nesta versão — diferente de `billing-service` (verificação de vencimento). Toda transição de status é reativa: disparada por uma chamada HTTP de criação ou por um webhook recebido. Não há "verificação de pagamentos pendentes" agendada nesta versão (não pedida pelo documento funcional).

---

## Por que um único deployável (e não um por Bounded Context)

Este serviço não tem nenhum processamento de longa duração a desacoplar: toda operação (criação, consulta, webhook) é resolvida na mesma requisição HTTP, com uma transação de banco no máximo, mais eventualmente uma ou mais chamadas HTTP síncronas de saída (provedor, `Billing Service`, `Person Service`, `Notification Service`). Separar BC-01/BC-02 em deployáveis distintos hoje adicionaria complexidade operacional sem nenhum ganho correspondente — mesmo racional já aplicado por `billing-service`/`person-service`/`storage-service`.

---

## Eventos internos (não cruzam processo)

Todos os eventos de domínio nomeados em `dominio/02-event-stories.md`/`05-bounded-contexts.md` são publicados apenas em um **despachante de eventos em memória**, dentro do único processo do Payment API, consumidos em processo pelo módulo de Auditoria (BC-02) — mesma decisão de implantação inicial já registrada por `billing-service`/`person-service`/`storage-service` (`18-event-contracts.md`).

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
