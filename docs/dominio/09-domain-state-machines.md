# Máquinas de Estado — Payment Service

> Formaliza, em diagrama e tabela de transição, o ciclo de vida já descrito textualmente no documento funcional (seções 9-10) e em `03-business-decisions.md` (BD-07, BD-08). Mesmo formato de `billing-service`/`person-service`/`storage-service`.

---

## Máquina 1 — Status do Payment

**Aplica-se a:** `payments.status`.

```text
                 ┌──────────────┐
                 │   PENDING     │  (estado inicial)
                 └───┬─┬────────┘
                     │ │
        ┌────────────┘ └────────────┐
        ▼                            ▼
┌────────────────┐            ┌───────────┐
│   PROCESSING     │            │ CANCELLED │ (terminal)
└───┬─────────┬────┘            └───────────┘
    │         │
    ▼         ▼
┌──────────┐ ┌──────────┐
│ APPROVED  │ │ REJECTED  │ (terminal)
└─┬──────┬──┘ └──────────┘
  │      │
  ▼      ▼
┌────────┐ ┌────────────────────┐
│REFUNDED │ │ PARTIALLY_REFUNDED  │
│(terminal)│ │ (terminal nesta     │
└────────┘ │ versão — ver Evolução)│
           └────────────────────┘
```

Representação em tabela (fonte da verdade):

| De | Para | Gatilho | Regra |
|---|---|---|---|
| — | `PENDING` | Criação do Payment (ES-01) | Estado inicial, sempre. |
| `PENDING` | `PROCESSING` | Envio síncrono ao provedor aceito (ES-01, mesma operação de criação) | Assumido\* como parte da própria criação — se o envio falhar, o Payment permanece `PENDING` (ver `12-acceptance-criteria.md`, Valores Assumidos). |
| `PENDING` | `CANCELLED` | Cancelamento (`POST /v1/payments/{id}/cancel`\*, assumido — Perfil `PAYMENT_CANCEL` existe, mas o endpoint não é explicitado literalmente pelo documento funcional; inferido pela combinação de Perfil + evento `PAYMENT_CANCELLED` + esta transição do diagrama da seção 10) | Só permitido a partir de `PENDING` — antes de qualquer envio ao provedor. |
| `PROCESSING` | `APPROVED` | Webhook do provedor confirma aprovação (ES-05/ES-06) | — |
| `PROCESSING` | `REJECTED` | Webhook do provedor confirma rejeição (ES-05/ES-06) | — |
| `APPROVED` | `REFUNDED` | Webhook do provedor reporta estorno total (ES-05/ES-06) | Só alcançável de forma reativa nesta versão — nenhum endpoint deste serviço inicia o estorno (BD-08, Hotspot H03). |
| `APPROVED` | `PARTIALLY_REFUNDED` | Webhook do provedor reporta estorno parcial (ES-05/ES-06) | Mesma ressalva acima — reativo, não iniciado por este serviço nesta versão. |

**Transições explicitamente proibidas** (documento funcional, seção 10):

```text
APPROVED   -> PENDING
APPROVED   -> REJECTED
REFUNDED   -> APPROVED
CANCELLED  -> APPROVED
```

**Estados terminais nesta versão:** `REJECTED`, `CANCELLED` e `REFUNDED` — nenhuma transição sai deles. `PARTIALLY_REFUNDED` é tratado como terminal nesta versão por ausência de qualquer transição definida a partir dele no documento funcional (nem para `REFUNDED`, nem para um novo `PARTIALLY_REFUNDED` cumulativo) — ver Evolução, abaixo. Não há reativação de nenhum estado terminal nesta versão (mesmo princípio de `billing-service`/`storage-service`).

**Nota sobre `PROCESSING → PENDING`:** não existe transição de volta de `PROCESSING` para `PENDING` no documento funcional — uma vez que o provedor aceitou processar a operação, o Payment nunca "desprocessa"; se o provedor rejeitar antes de qualquer confirmação, o resultado é `REJECTED`, nunca um retorno a `PENDING`.

---

## Evolução

Revisar esta máquina quando: o Hotspot H01 (provedor real) for resolvido — pode revelar estados intermediários específicos do provedor escolhido (ex.: `AWAITING_PAYER_ACTION` para Pix, se o provedor distinguir "aguardando o pagador agir" de "processando internamente"); o Hotspot H03 (estorno) for resolvido — a introdução de `POST /v1/payments/{id}/refund` provavelmente exigirá definir se múltiplos estornos parciais podem se acumular até atingir `REFUNDED`, ou se um único `PARTIALLY_REFUNDED` já é terminal por decisão de negócio.
