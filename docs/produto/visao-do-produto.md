# Visão do Produto — Payment Service

## 1. Objetivo

Criar um **serviço centralizado de processamento de pagamentos** — o único ponto pelo qual qualquer sistema corporativo movimenta dinheiro de fato, nos dois sentidos: recebendo de um cliente ou pagando a uma pessoa/empresa.

O `Payment Service` representa a **movimentação financeira** (como um valor é efetivamente transferido, através de qual meio, com qual provedor) — nunca a **obrigação financeira** em si (quanto se deve, para quem, até quando), responsabilidade exclusiva do `Billing Service`. Mesma filosofia de especialização já adotada por `auth-service` (identidade), `Person Service` (dados cadastrais), `Storage Service` (arquivos) e `Billing Service` (obrigação financeira): uma capacidade corporativa compartilhada, consumida via API, que abstrai a complexidade de manter esse dado localmente em cada sistema.

`Billing Service` e `Payment Service` dividem o mesmo domínio maior ("cobrar e pagar") em duas responsabilidades deliberadamente separadas — mesma regra arquitetural principal já estabelecida quando `billing-service` foi documentado, agora formalizada do lado que a executa: `Billing Service` decide *que valor é devido*; `Payment Service` decide *como esse valor é efetivamente movimentado*.

## 2. Escopo

O `Payment Service` cria e controla, para cada pagamento:

* o sentido da movimentação (`type`: `RECEIVE` — a empresa recebe — ou `PAY` — a empresa paga);
* a cobrança relacionada (`billingId`, referência opaca ao `Billing Service`);
* o valor e a moeda, com precisão decimal;
* o meio de pagamento utilizado (`method` — só `PIX` implementado nesta versão);
* o provedor de pagamento utilizado e o identificador que ele atribuiu à operação;
* o status corrente, segundo uma máquina de estados fechada;
* o histórico completo de toda mudança de status;
* o registro de toda tentativa de pagamento, mesmo as recusadas.

O serviço é responsável por:

* criar pagamentos de forma idempotente (`idempotencyKey`), sempre associados a uma cobrança já existente no `Billing Service`;
* comunicar-se com provedores de pagamento externos, através de uma abstração que isola o restante da aplicação do contrato específico de cada provedor;
* controlar a transição de status (`PENDING` → `PROCESSING` → `APPROVED`/`REJECTED`/`CANCELLED`), nunca permitindo transições arbitrárias;
* receber webhooks dos provedores, de forma idempotente, e atualizar o status do pagamento correspondente;
* consultar pagamentos por identificador ou por cobrança relacionada, com paginação;
* obter, junto ao `Person Service`, os dados de destino necessários para executar um pagamento (`PAY`) — sem jamais armazenar esse dado além do estritamente necessário para a operação em curso;
* informar o `Billing Service` quando um pagamento for aprovado, rejeitado, cancelado ou estornado;
* publicar eventos de alteração de pagamento, para que o `Notification Service` decida como comunicar o resultado ao usuário final;
* registrar histórico e auditoria de toda operação financeira relevante.

O serviço **não** é responsável por: criar pedidos, criar cobranças, controlar vencimento de cobranças, controlar contas a receber/a pagar, cadastrar pessoas, armazenar documentos, ou enviar notificações (e-mail, SMS, WhatsApp, push) diretamente — todas essas responsabilidades pertencem a outros serviços já existentes (`Order Service`, `Billing Service`, `Person Service`, `Notification Service`).

## 3. Arquitetura conceitual

```text
┌─────────────────────────────────────────────────────┐
│                 SISTEMAS CORPORATIVOS                │
│   Billing Service      Order Service    Painel Admin  │
└────────────────────────┬───────────────────────────────┘
                          │ REST / HTTP / JWT (auth-service)
                          ▼
┌─────────────────────────────────────────────────────┐
│                  PAYMENT SERVICE API                  │
│  Autenticação/Autorização (delegadas — auth-service)  │
│  Criação · Consulta · Webhook · Histórico                │
│  Máquina de Status · Idempotência · Auditoria           │
│  Abstração PaymentProvider                              │
└───┬─────────────────────────────────────────┬───────────┘
    │                                         │
    ▼                                         ▼ (HTTP síncrono)
┌───────────────────────────────┐   ┌──────────────────────────┐
│           POSTGRESQL            │   │  Billing Service /        │
│  payments · payment_status_     │   │  Person Service /         │
│  history · payment_provider_    │   │  Notification Service     │
│  events · audit_logs             │   └──────────────────────────┘
└───────────────────────────────┘
              │
              ▼ (HTTP síncrono outbound + webhook inbound)
     ┌─────────────────────┐
     │   Payment Provider    │
     │   (ex.: PROVIDER_A —   │
     │   assumido, ver H01)   │
     └─────────────────────┘
```

Serviço inteiramente síncrono (API REST sobre PostgreSQL) — **sem mensageria de negócio** nesta versão, mesmo perfil já adotado por `billing-service`: a comunicação com `Billing Service`/`Person Service`/`Notification Service`/provedor é HTTP direto. Ver `arquitetura/13-architecture.md` e ADR-010 (desvio deliberado do padrão organizacional de mensageria, mesma justificativa e mesmo padrão já registrado por `billing-service`, seção 2 de `padrao-desenvolvimento.md`). RabbitMQ é usado **exclusivamente para publicar auditoria** no `audit-service` (`audit.events`, `padrao-desenvolvimento.md` seção 17) — a comunicação de negócio permanece HTTP síncrona; ver ADR-010.

## 4. Comunicação com sistemas consumidores

API REST autenticada via **JWT emitido pelo `auth-service`** (delegação total — ver seção 6 e ADR-001).

```http
POST /v1/payments
Authorization: Bearer <JWT>
Content-Type: application/json
```

```json
{
  "type": "RECEIVE",
  "billingId": "650e8400-e29b-41d4-a716-446655440000",
  "amount": 150.90,
  "currency": "BRL",
  "method": "PIX",
  "idempotencyKey": "ORDER-123456-PAYMENT"
}
```

O sistema consumidor guarda o `id` retornado (`paymentId`) — nunca reimplementa controle de status próprio sobre o pagamento. Consulta e acompanhamento usam esse mesmo identificador — ver `contratos/17-api-contracts.md`.

## 5. Princípios arquiteturais

* **Pagamento é movimentação, não obrigação** — o `Payment Service` nunca decide quanto é devido, só executa e confirma a movimentação de um valor já definido pelo `Billing Service` (BD-01).
* **`paymentId` como identificador universal** — nunca o identificador do provedor (`providerPaymentId`); os demais serviços referenciam o pagamento só pelo UUID interno.
* **Cada serviço é dono do próprio banco** — o `Payment Service` nunca acessa diretamente o banco de dados do `Billing Service`, nem o contrário; toda comunicação é via API/evento (seção 26 do documento funcional).
* **Máquina de estados fechada** — nenhuma transição de status fora do catálogo explícito é permitida; nenhum estado terminal (`APPROVED` sem estorno, `REJECTED`, `CANCELLED`) é reaberto para os estados anteriores.
* **Tentativa nova, `Payment` novo** — um pagamento recusado nunca é reaproveitado para uma nova tentativa; cada tentativa é um registro próprio, imutável quanto ao seu resultado original.
* **Sem replicação de dado cadastral, nem de dado financeiro de destino** — o pagador/recebedor é resolvido via `personId`; `Person Service` é a fonte oficial de CPF/CNPJ, chave Pix e conta bancária. O `Payment Service` nunca armazena mais desse dado do que o estritamente necessário para executar a operação em curso.
* **Idempotência por padrão** — toda criação exige `idempotencyKey`; todo webhook exige `providerEventId` — a mesma requisição/evento nunca produz duas operações.
* **Precisão decimal sempre** — nenhum cálculo financeiro usa `float`.
* **Provedor é detalhe de infraestrutura, não de domínio** — a abstração `PaymentProvider` isola o restante da aplicação do contrato específico de cada provedor; trocar de provedor não deve exigir mudança de regra de negócio.
* **Segurança por padrão** — autenticação/autorização sempre delegadas ao `auth-service`; nunca implementação própria.

## 6. Segurança (visão geral)

Autenticação via JWT emitido pelo `auth-service` (ADR-001); autorização por Perfil (`PAYMENT_READ`, `PAYMENT_CREATE`, `PAYMENT_CANCEL`, `PAYMENT_REFUND`), concedidos por aplicação; nenhuma operação financeira sem autorização explícita; nunca persistir JWT, `client_secret`, senha, chave privada, CVV, senha bancária ou credencial de banco; nenhum dado sensível em log; auditoria das operações financeiras relevantes. Ver `dominio/03-business-decisions.md` e `requisitos/11-non-functional-requirements.md`.

**API de Configuração (`/admin/config`).** Por adoção do padrão organizacional (`padrao-desenvolvimento.md` seção 23; `codepump/docs/padroes-implementacao/padrao-api-config.md`), este serviço passa a expor uma API de configuração `GET /admin/config` — servida pela própria aplicação Go (`html/template` + HTMX + CSS, sem SPA), protegida por perfil administrativo (seção 9), contraparte humana do `/props` (seção 16) — para administrar sua configuração programável (timeouts de chamada, provedor de pagamento ativo, parâmetros operacionais), nunca segredos, que permanecem no OpenBao. Mudanças de configuração são auditadas via `AuditEvent` canônico (seção 17). Detalhes e categorias em `arquitetura/decisoes/ADR-020-api-configuracao.md`.

## 7. Observabilidade (visão geral)

Logs estruturados (padrão organizacional, `padrao-desenvolvimento.md` seção 7.2), com `paymentId`/`billingId`/`provider`/`providerPaymentId`/`status`/`operation`/`correlationId`; health checks. Correlation ID (`X-Correlation-ID`) propagado para `Billing Service`, provedor e `Notification Service`, para rastrear uma operação completa de ponta a ponta.

## 8. Escalabilidade (visão geral)

API stateless, escalável horizontalmente atrás de um load balancer — mesma decisão de infraestrutura padrão (PostgreSQL em instância única no MVP, `arquitetura/15-infrastructure.md`).

## 9. Stack tecnológica

Adoção direta do padrão organizacional (`codepump/codepump/docs/padrao-desenvolvimento.md`), com o mesmo desvio deliberado e documentado já adotado por `billing-service` (comunicação HTTP direta em vez de RabbitMQ, ADR-010):

```text
Backend            Go (Golang) — ADR-002
Framework HTTP     net/http + http.ServeMux — ADR-003
API                REST, prefixo /v1 — ADR-005
Banco              PostgreSQL, via pgx/pgxpool, sem ORM — ADR-003
Migração de schema golang-migrate — ADR-003
JWT                golang-jwt/v5, emitido e validado via auth-service — ADR-001
Segredos           OpenBao (Secrets Manager centralizado) — ADR-008
Logs               /apps/logs/[namespace]/payment-service/, JSON estruturado — ADR-009
Integrações        HTTP síncrono (Billing Service, Person Service, Notification Service, Provedor) — ADR-010; RabbitMQ só para auditoria (audit.events) — seção 17
Auditoria          audit-service via RabbitMQ (audit.events, AuditEvent da codepump-lib) — padrão, seções 17/18
Infraestrutura     PostgreSQL em instância única no MVP — ADR-007/15-infrastructure.md
Lib compartilhada  codepump-lib — funcionalidades técnicas padronizadas (padrão, seção 18)
```

## 10. Escopo da Primeira Versão (MVP)

```text
Sistema Consumidor / Billing Service → Payment Service API → PostgreSQL
                                              │
                                              ▼ (HTTP síncrono)
                                     Payment Provider / Person Service / Notification Service
```

Com os seguintes recursos: JWT (delegado ao `auth-service`); criação de pagamento idempotente, nos dois sentidos (`RECEIVE`/`PAY`); consulta por `id` e por `billingId` (com paginação); meio de pagamento `PIX`; controle de status fechado (`PENDING`/`PROCESSING`/`APPROVED`/`REJECTED`/`CANCELLED`); histórico de toda mudança de status; webhook de confirmação do provedor, idempotente por `providerEventId`; integração com um único provedor (nome real ainda não definido — Hotspot H01); integração com `Billing Service` (consulta de valor disponível, informe de resultado); integração com `Person Service` (dados de destino para `PAY`); auditoria; Docker Compose.

**Fora do MVP** (seção 36 da especificação fornecida pelo usuário): múltiplos provedores simultâneos, múltiplas moedas, parcelamento complexo, split de pagamento, marketplace financeiro, antecipação, conta digital, carteira digital, conciliação bancária automática, estorno (total ou parcial — ver seção 11, abaixo, e Hotspot H03), recorrência, assinaturas, boleto, múltiplos adquirentes.

## 11. Estornos: modelados, mas não implementados nesta versão

O catálogo de status inclui `REFUNDED`/`PARTIALLY_REFUNDED` desde a primeira versão (domínio fechado, seção 9 da especificação) — mas a lista explícita de "Primeira Versão" (seção 35) não inclui o endpoint `POST /payments/{id}/refund`, e a seção 24 abre com "Implemente posteriormente o estorno". A leitura desta documentação: os dois status existem no modelo (e são alcançáveis via webhook, se o próprio provedor reportar um estorno iniciado fora deste serviço), mas nenhum endpoint deste serviço **inicia** um estorno nesta versão — ver BD-11 e `09-domain-state-machines.md`.

## 12. Pontos em aberto

Ver `dominio/01-event-storming-big-picture.md`, seção Hotspots: o provedor real a integrar na primeira versão não está definido (H01); o mecanismo exato de assinatura/autenticidade do webhook depende do provedor escolhido (H02); e o momento em que o próprio `Payment Provider` reporta um estorno fora do fluxo de criação deste serviço não está detalhado pela especificação (H03).

## 13. Evolução futura

Introdução de RabbitMQ quando a necessidade de desacoplamento/processamento assíncrono justificar (ADR-010); múltiplos provedores simultâneos, com escolha por regra de negócio (custo, disponibilidade, meio de pagamento); estorno total e parcial via endpoint próprio; múltiplas moedas; parcelamento; split de pagamento; conciliação bancária automatizada.

## 14. Resultado esperado

Os sistemas corporativos devem enxergar o `Payment Service` como o único lugar onde dinheiro de fato muda de mãos:

```text
BILLING SERVICE → "Esta cobrança RECEIVABLE de R$ 150,90 precisa ser paga pelo cliente."
PAYMENT SERVICE → cria o Payment (RECEIVE/PIX), envia ao provedor, retorna os dados para o cliente pagar.
PAYMENT PROVIDER → processa a operação, confirma via webhook.
PAYMENT SERVICE → atualiza o Payment para APPROVED, informa o Billing Service.
BILLING SERVICE → atualiza a Cobrança para PAID.
```

Benefício esperado: separar claramente "quanto se deve" (`Billing Service`) de "como o dinheiro efetivamente se move" (`Payment Service`), permitindo trocar de provedor de pagamento sem tocar em nenhuma regra de cobrança, e mantendo rastreabilidade completa de toda tentativa de movimentação financeira.
