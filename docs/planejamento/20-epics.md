# Planejamento — Épicos

> Agrupa os 9 Requisitos Funcionais (`../requisitos/10-functional-requirements.md`, RF-01 a RF-09) em Épicos, seguindo os Bounded Contexts (`../dominio/05-bounded-contexts.md`). Mesmo formato de `billing-service`/`person-service`/`storage-service`.

---

## Convenção

Cada Épico traz: Objetivo, Bounded Context principal, Histórias incluídas (RF-XX), e Dependências de outros Épicos. Detalhe de cada História em `21-user-stories.md`.

---

## E1 — Payment

**Objetivo:** criar e consultar pagamentos, sempre com idempotência, precisão decimal e uma cobrança relacionada já validada (BD-02, BD-05, BD-09, BD-11).

**Bounded Context principal:** Payment (BC-01).

**Histórias:** RF-01 (Criação, incluindo a obtenção de dados do recebedor para `PAY`, RF-04), RF-02 (Consulta por ID), RF-03 (Consulta por Cobrança), RF-08 (Histórico de Status).

**Dependências de outros Épicos:** nenhuma — é o Épico fundamental. Depende de duas integrações externas já documentadas (`Billing Service`, `Person Service`) e de uma integração ainda não formalizada (`Payment Provider`, Hotspot H01).

---

## E2 — Confirmação do Provedor

**Objetivo:** receber, de forma idempotente e autenticada, o resultado de uma operação processada pelo `Payment Provider`, e refletir esse resultado no Payment (BD-07, BD-08, BD-10).

**Bounded Context principal:** Payment (BC-01).

**Histórias:** RF-05 (Recebimento de Webhook), RF-06 (Atualização de Status por Confirmação do Provedor).

**Dependências de outros Épicos:** depende de E1 (Payment já criado) — dependência de **runtime**. Depende de uma integração externa ainda não formalizada (`Payment Provider`, Hotspot H01/H02) — a implementação pode começar com um contrato assumido, mas exigirá ajuste quando o provedor real for escolhido.

---

## E3 — Integração com Billing Service

**Objetivo:** propagar ao `Billing Service` o resultado de uma movimentação financeira, para que a obrigação correspondente seja atualizada (BD-01).

**Bounded Context principal:** Payment (BC-01).

**Histórias:** RF-07 (Informar Billing Service do Resultado).

**Dependências de outros Épicos:** depende de E2 (resultado já aplicado ao Payment) — dependência de **runtime**. Depende do contrato já assumido do lado de `billing-service` (`POST /v1/billings/{id}/payment-events`\*).

---

## E4 — Auditoria

**Objetivo:** registrar toda operação financeira relevante dos demais Épicos, sem duplicar dado sensível (BD-15, BD-18).

**Bounded Context principal:** Auditoria (BC-02).

**Histórias:** RF-09 (Auditoria de Operações).

**Dependências de outros Épicos:** depende de E1, E2 (consome os eventos internos publicados por ambos — `06-context-map.md`) — mas não bloqueia nenhum deles: cada operação de escrita já responde ao chamador antes/independentemente do resultado da gravação de auditoria.

---

## Ordem Sugerida de Implementação

1. **E1** (Payment) — primeiro, por ser pré-requisito de runtime de E2 e E3, e por conter a maior parte da superfície de API.
2. **E4** (Auditoria) — em paralelo a E1, já que é consumida por todos os demais Épicos desde o início.
3. **E2** (Confirmação do Provedor) — depende de E1; maior risco de retrabalho por depender de um provedor ainda não escolhido (Hotspot H01/H02) — considerar implementar atrás da abstração `PaymentProvider` (BD-13) desde o início, para isolar esse risco.
4. **E3** (Integração com Billing Service) — por último entre os quatro, já que depende de E2 já estar funcionando; contrato reaproveitado de `billing-service`, risco de retrabalho menor que E2.

---

## Pontos a Definir

* **Estimativa de esforço/tamanho de cada Épico ou História** não é definida por nenhum documento de domínio, arquitetura ou requisitos — responsabilidade da equipe de desenvolvimento ao iniciar o Épico.
* **E2 tem o maior risco de retrabalho** deste plano — depende diretamente da escolha do provedor real (Hotspot H01) e do mecanismo de autenticidade de webhook (Hotspot H02); implementá-lo atrás da abstração `PaymentProvider` (BD-13, ADR-015) reduz, mas não elimina, esse risco.
