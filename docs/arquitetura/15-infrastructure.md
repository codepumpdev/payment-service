# Infraestrutura — Payment Service

> Cobre decisões de implantação e operação que não são regra de negócio (`../dominio/03-business-decisions.md`) nem arquitetura de componentes (`13-architecture.md`). Formalizado por ADR-007 (PostgreSQL), ADR-008 (segredos) e ADR-010 (comunicação HTTP síncrona). Adoção direta do padrão organizacional (`codepump/codepump/docs/padrao-desenvolvimento.md`, seções 8 e 8.1), com um desvio deliberado (ADR-010), mesmo perfil de `billing-service`.

---

## PostgreSQL — Topologia (ADR-007)

* **Instância única no MVP** — sem cluster, sem réplica de leitura, sem failover automático.
* **Sem backup/restauração automatizados configurados inicialmente** — decisão padrão do MVP organizacional, sem desvio (mesma decisão de `billing-service`; diferente de `storage-service`, que optou por backup desde o MVP por natureza do próprio domínio).
* Ponto único de falha (SPOF) aceito deliberadamente no MVP.

---

## Gestão de Segredos Operacionais (ADR-008)

Adoção direta do padrão organizacional — OpenBao como Secrets Manager centralizado, desde a primeira ADR de infraestrutura deste serviço (`padrao-desenvolvimento.md`, seção 8.1).

* **Senha de conexão do PostgreSQL** — vai integralmente ao OpenBao, lida na inicialização, mantida em memória durante a execução.
* **Credencial M2M própria** (`client_id`/`client_secret`, para obter Token de Serviço ao chamar `Billing Service`/`Person Service`/`Notification Service`) — vai ao OpenBao, mesmo tratamento.
* **Credencial de integração com o Payment Provider** (chave de API, segredo de assinatura do webhook — Hotspot H01/H02) — vai integralmente ao OpenBao, mesmo tratamento dado a credenciais de provedor externo por `notification-service` (ADR-009 daquele serviço).
* Organização por ambiente: `kv/<ambiente>/payment-service/`.

Nenhum segredo emitido por este serviço a terceiros (nenhum `client_secret` próprio distribuído) — a distinção hash-only vs. OpenBao (`padrao-desenvolvimento.md`, seção 8.1) não se aplica aqui; este serviço só **consome** segredos, nunca emite.

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
