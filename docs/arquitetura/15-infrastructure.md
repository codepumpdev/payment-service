# Infraestrutura — Payment Service

> Cobre decisões de implantação e operação que não são regra de negócio (`../dominio/03-business-decisions.md`) nem arquitetura de componentes (`13-architecture.md`). Formalizado por ADR-007 (PostgreSQL), ADR-008 (segredos), ADR-010 (comunicação HTTP síncrona), ADR-018 (banco de dados exclusivo) e ADR-019 (Health Check/Readiness Check/Identificação de Build). Adoção direta do padrão organizacional (`codepump/codepump/docs/padrao-desenvolvimento.md`, seções 8, 8.1, 8.2, 12 e 17 — Auditoria Centralizada via RabbitMQ, adotada em 2026-08-14), com um desvio deliberado, restrito à comunicação de negócio (ADR-010), mesmo perfil de `billing-service`.

---

## PostgreSQL — Topologia (ADR-007)

* **Instância única no MVP** — sem cluster, sem réplica de leitura, sem failover automático.
* **Sem backup/restauração automatizados configurados inicialmente** — decisão padrão do MVP organizacional, sem desvio (mesma decisão de `billing-service`; diferente de `storage-service`, que optou por backup desde o MVP por natureza do próprio domínio).
* Ponto único de falha (SPOF) aceito deliberadamente no MVP.
* **Banco de dados lógico exclusivo: `payment`** (`CREATE DATABASE payment`, ADR-018) — adoção do padrão organizacional (`padrao-desenvolvimento.md`, seção 8.2). Nenhum outro serviço da organização acessa este banco, direta ou indiretamente (nem tabela, nem schema, nem view). A instância física PostgreSQL pode ser compartilhada com o banco lógico de outro serviço por economia de infraestrutura no MVP (acima) — o banco lógico, nunca.

### Conexões Command e Query (CQRS — seção 15 do padrão)

Este serviço expõe duas conexões nomeadas, configuráveis de forma independente desde a primeira versão:

```properties
COMMAND_DATABASE_URL=postgresql://postgres:5432/payment
QUERY_DATABASE_URL=postgresql://postgres:5432/payment
```

**No MVP as duas apontam para o mesmo banco** — o banco `payment`, exclusivo deste serviço (seção 8.2) — com o mesmo usuário e a mesma senha, lidos de `secret/payment-service/database/command` e `.../query`. A separação é de código, interface e configuração; nunca se cria um segundo banco só para satisfazer o padrão.

Os pools são independentes (`COMMAND_POOL`/`QUERY_POOL`, `MAX_CONNECTIONS` próprio), e o código nunca assume que as duas URLs apontam para o mesmo lugar. Quando houver necessidade real de escala de leitura, separar os bancos passa a ser mudança de configuração e dos dois secrets — sem alteração de código.

---

## Gestão de Segredos Operacionais (ADR-008)

Adoção direta do padrão organizacional — OpenBao como Secrets Manager centralizado, desde a primeira ADR de infraestrutura deste serviço (`padrao-desenvolvimento.md`, seção 8.1).

* **Senha de conexão do PostgreSQL** — vai integralmente ao OpenBao, lida na inicialização, mantida em memória durante a execução.
* **Credencial M2M própria** (`client_id`/`client_secret`, para obter Token de Serviço ao chamar `Billing Service`/`Person Service`/`Notification Service`) — vai ao OpenBao, mesmo tratamento.
* **Credencial de integração com o Payment Provider** (chave de API, segredo de assinatura do webhook — Hotspot H01/H02) — vai integralmente ao OpenBao, mesmo tratamento dado a credenciais de provedor externo por `notification-service` (ADR-009 daquele serviço).
* **Credencial de conexão do RabbitMQ** (para publicar em `audit.events` — adicionada em 2026-08-14, ADR-010/§17) — vai integralmente ao OpenBao, lida na inicialização, mantida em memória durante a execução.
* Prefixo no OpenBao: `secret/payment-service/` — o isolamento entre ambientes é por servidor (uma instância de OpenBao por ambiente), não por segmento no caminho.

Nenhum segredo emitido por este serviço a terceiros (nenhum `client_secret` próprio distribuído) — a distinção hash-only vs. OpenBao (`padrao-desenvolvimento.md`, seção 8.1) não se aplica aqui; este serviço só **consome** segredos, nunca emite.

### Paths no OpenBao

Paths concretos deste serviço, na convenção da seção 8.1 do padrão. A policy autoriza `read` em cada um, e em nada fora do prefixo `secret/payment-service/`:

| Path | Campos | Observação |
|---|---|---|
| `secret/payment-service/database/command` | `payment_owner_user`, `payment_owner_password`, `payment_app_user`, `payment_app_password` | Conexão **Command** (seção 15 do padrão). |
| `secret/payment-service/database/query` | os mesmos quatro campos | Conexão **Query**. Mesmo banco no MVP, portanto **mesmo usuário e mesma senha** de `database/command`. |
| `secret/payment-service/m2m` | `client_id`, `client_secret` | Credencial de Aplicação própria, usada para obter Token de Serviço M2M no `auth-service`. |
| `secret/payment-service/providers/payment` (e `/*`) | definidos pelo fornecedor | **Path autorizado, sem secret criado.** Cada provedor recebe o seu sob demanda — ex.: `secret/payment-service/providers/payment/<fornecedor>`. |

Provisionados por `scripts/openbao/setup-payment-service.cmd`, que é a fonte da verdade destes paths — um secret que já existe é preservado pelo script.

As senhas de banco são geradas pelo script do OpenBao e depois usadas no `scripts/postgres/database.cmd` — o OpenBao é a origem, o banco é o consumidor, nunca o contrário.

---

## Armazenamento de Logs (ADR-009)

Adoção direta do padrão organizacional (`padrao-desenvolvimento.md`, seção 7.2).

* **Diretório:** `/apps/logs/prod/payment-service/`, volume compartilhado, fora do container.
* **Arquivos:** `payment-service-[date]-[pod-id]-[sequence].log`/`.err`, JSON estruturado (`log/slog`).
* **Limites:** 10 MB por arquivo, 10 arquivos, 100 MB por aplicação — remoção automática do arquivo mais antigo.
* **Dados sensíveis:** nunca JWT, `client_secret`, senha, chave privada, CVV, senha bancária, credencial de banco, dado bancário completo (BD-15).

---

## Comunicação HTTP Síncrona com Serviços Externos (ADR-010)

**Desvio deliberado do padrão organizacional** (`padrao-desenvolvimento.md`, seção 2 — RabbitMQ como padrão para comunicação assíncrona): `Payment Service` se comunica com `Billing Service`, `Person Service`, `Notification Service` e `Payment Provider` via chamada HTTP síncrona nesta versão, sem fila — mesma decisão já adotada por `billing-service` (ADR-010 daquele serviço).

* **Inbound:** `Payment Provider` chama `Payment Service` diretamente (`POST /v1/payments/webhooks/{provider}`), autenticado por mecanismo próprio do provedor (Hotspot H02), não por JWT do `auth-service`.
* **Outbound:** `Payment Service` chama `Billing Service` (consulta de valor disponível + informe de resultado), `Person Service` (dados de recebimento) e `Notification Service` (publicação de evento) diretamente, autenticado com Token de Serviço M2M próprio; chama o `Payment Provider` (envio da operação) com a credencial específica daquele provedor.
* Nenhum retry automático interno nesta versão — falha de chamada outbound não desfaz a transação de banco já commitada; reprocessamento é responsabilidade operacional (assumido\*, ver `12-acceptance-criteria.md`).

---

## RabbitMQ — Uso Exclusivo para Auditoria (2026-08-14, ADR-010/§17)

Adoção do padrão organizacional de Auditoria Centralizada (`padrao-desenvolvimento.md`, seção 17). Diferente de `notification-service` (mensageria como núcleo do produto), `payment-service` usa RabbitMQ **exclusivamente** para publicar eventos de auditoria no exchange `audit.events` — nenhuma fila própria de negócio, nenhum consumo de mensagens. A comunicação de negócio (`Billing Service`/`Person Service`/`Notification Service`/`Payment Provider`) permanece em HTTP síncrono (ADR-010, acima); o broker existe só para auditoria. Mesmo padrão de `organization-service` (ADR-011) e `alert-service` (ADR-010).

* **Exchange publicado:** `audit.events` (`topic`, durable) — este serviço é **publicador**, nunca consumidor (consumo é exclusivo de `audit-service`).
* **Routing key:** `audit.event.published`.
* **Confirmação de publicação:** Publisher Confirms habilitado — publicação não confirmada é falha, nunca sucesso silencioso.
* **Cliente Go:** `rabbitmq/amqp091-go` (`padrao-desenvolvimento.md`, seção 2).
* **Formato:** `AuditEvent` canônico da `codepump-lib` (`padrao-desenvolvimento.md`, seções 17.3/18) — mapeamento das operações financeiras (BD-18) em `contratos/18-event-contracts.md`.
* **Credencial de conexão** gerida via OpenBao (ADR-008; ver Gestão de Segredos Operacionais, acima).
* **Falha de publicação nunca bloqueia a operação de negócio** — publicação best-effort, fora da transação já comitada / do processamento do webhook. RabbitMQ **não** é dependência do `GET /ready` (ADR-019) — coerente, pois a publicação de auditoria é assíncrona e best-effort.

---

## `build.properties` e Identificação de Build (ADR-019)

Adoção direta do padrão organizacional (`padrao-desenvolvimento.md`, seção 12.1).

* Gerado automaticamente durante o build (nunca manualmente pelo desenvolvedor), na raiz do artefato, pelo pipeline de CI/CD (etapa 13, hoje `Pendente`):
  ```properties
  branch=main
  commit=ba996ad8715
  buildDate=2026-08-13T14:30:00-03:00
  ```
* `branch`/`commit` vêm do processo de CI/CD (ou do build local) — nunca digitados manualmente; `buildDate` é o instante real de construção do artefato (ISO 8601 com timezone) — nunca o horário de inicialização do container. Um redeploy do mesmo artefato, sem novo build, nunca muda `buildDate`.
* Lido uma única vez na inicialização do processo Go, mantido em memória, e exposto em `GET /health` (`17-api-contracts.md`).

---

## Health Check e Readiness Check (ADR-019)

Adoção direta do padrão organizacional (`padrao-desenvolvimento.md`, seção 12.2/12.3) — `GET /health` (liveness) e `GET /ready` (readiness, verificando `database` e `auth-service`; `Billing Service`, `Person Service`, `Payment Provider`, `Notification Service`, OpenBao e RabbitMQ **não** entram nesse check — ver ADR-019 para o raciocínio completo, incluindo o Hotspot H04 sobre `Billing Service`/`Person Service`). Contrato completo em `contratos/17-api-contracts.md`.

---

## Escalabilidade e Volumetria — Referências Cruzadas

* A Payment API é stateless e escalável horizontalmente (`13-architecture.md`) — não depende da decisão de banco.
* Nenhuma meta de capacidade é fixada neste documento — ver `../requisitos/11-non-functional-requirements.md` (RNF-10).

---

## Pontos Abertos

* Estratégia de backup/replicação/alta disponibilidade do PostgreSQL — postergada até a volumetria real ser conhecida (ADR-007), mesmo critério de todos os serviços já documentados.
* Mecanismo de retry para chamadas HTTP outbound falhas — não definido nesta versão (ADR-010).
* Credencial/mecanismo exato de segurança do Payment Provider — depende de H01/H02.

---

## Evolução

* Definir estratégia de backup e considerar réplica de leitura/alta disponibilidade quando a volumetria real justificar.
* Introduzir RabbitMQ para as comunicações inbound/outbound quando a necessidade de desacoplamento for real (ADR-010).
