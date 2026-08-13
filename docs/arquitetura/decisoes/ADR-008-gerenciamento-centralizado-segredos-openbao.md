# ADR-008 — Gerenciamento Centralizado de Segredos: OpenBao

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 8.1, origem: ADR-017 de `auth-service`) fixa OpenBao como Secrets Manager centralizado padrão para todo novo serviço, desde a primeira ADR de infraestrutura. `Payment Service` tem uma necessidade adicional em relação a `billing-service`: credenciais de integração com o `Payment Provider` (chave de API, segredo de assinatura de webhook) — segredos que o serviço **lê**, nunca emite, mesmo perfil de credencial de provedor já tratado por `notification-service` (ADR-009 daquele serviço).

## Decisão

`Payment Service` lê do OpenBao, na inicialização: a senha de conexão do PostgreSQL; a Credencial M2M própria (`client_id`/`client_secret`) para chamar `Billing Service`/`Person Service`/`Notification Service`; e a credencial de integração com o `Payment Provider` (chave de API e segredo de assinatura de webhook, Hotspot H01/H02) — todos mantidos em memória durante a execução, nunca em variável de ambiente, código-fonte ou banco de dados da aplicação.

## Consequências

### Positivas

- Nenhum segredo operacional (incluindo credencial de provedor externo, o mais sensível deste serviço) exposto em configuração ou banco.

### Negativas

- Nenhuma identificada — mesmo padrão já validado por `auth-service`, `notification-service`, `person-service`, `storage-service`, `billing-service`.

## Critérios para reavaliar

Quando o Hotspot H01 for resolvido (provedor real escolhido) — atualizar a estrutura de segredo específica daquele provedor, se divergir do formato genérico assumido aqui.

## Nota de integração

* `arquitetura/15-infrastructure.md`.
* `dominio/03-business-decisions.md` (BD-04).
* `codepump/codepump/docs/padrao-desenvolvimento.md`, seção 8.1.
