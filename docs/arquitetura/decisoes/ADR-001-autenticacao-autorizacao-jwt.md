# ADR-001 — Autenticação e Autorização via JWT (Delegadas ao `auth-service`)

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 9.1) fixa `auth-service` como Serviço Central de Autenticação e Autorização — nenhum novo serviço implementa login, emissão ou validação própria de JWT. `Payment Service` tem consumidores de dois perfis: sistemas automatizados (`Billing Service`, `Order Service`, aplicações de checkout) e, potencialmente, um painel administrativo futuro (fora do escopo desta versão) — ambos resolvidos pela mesma delegação.

## Decisão

`Payment Service` delega inteiramente autenticação e autorização ao `auth-service`. Toda rota (exceto `/health` e o webhook do provedor, `POST /v1/payments/webhooks/{provider}` — ver ADR-016\* nota: mecanismo próprio do provedor) exige JWT válido, assinado com RS256, validado contra a chave pública de `auth-service` (`GET /v1/auth/public-key`, cache local com atualização por `kid` desconhecido). Aplicações se autenticam via `client_id`/`client_secret`, obtendo Token de Serviço M2M (`POST /oauth2/v1/token/service`). Autorização por Perfil: `PAYMENT_READ`, `PAYMENT_CREATE`, `PAYMENT_CANCEL`, `PAYMENT_REFUND` — nenhum concedido por padrão.

## Consequências

### Positivas

- Nenhuma reimplementação de autenticação; mesmo modelo de todos os serviços já documentados (`billing-service`, `person-service`, `storage-service`, `notification-service`).
- Biblioteca já fixada (`github.com/golang-jwt/jwt/v5`) — sem decisão adicional a tomar.

### Negativas

- Dependência de disponibilidade de `auth-service` para qualquer operação — mitigado por cache local da chave pública (não exige chamada síncrona por requisição, só para obter/atualizar a chave).

## Critérios para reavaliar

Nenhum identificado — delegação total é o padrão organizacional desde `padrao-desenvolvimento.md` seção 9.1, sem exceção conhecida para este serviço.

## Nota de integração

* `dominio/03-business-decisions.md` (BD-04).
* `contratos/17-api-contracts.md`.
* `codepump/codepump/docs/padrao-desenvolvimento.md`, seções 9.1-9.3.
