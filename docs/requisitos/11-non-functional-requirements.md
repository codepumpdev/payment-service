# Requisitos Não Funcionais — Payment Service

> Mesmo formato de `billing-service`/`person-service`/`storage-service`: cada RNF cita a origem (documento funcional e/ou `padrao-desenvolvimento.md`) e, quando aplicável, a decisão de negócio/ADR que a fundamenta.

---

## Desempenho e Escalabilidade

### RNF-01 — API Stateless, Escalável Horizontalmente

Nenhuma sessão/estado em memória entre requisições; múltiplas instâncias atrás de um load balancer, sem coordenação entre elas além do PostgreSQL compartilhado. Mesma decisão de todos os serviços já documentados (`arquitetura/13-architecture.md`).

### RNF-02 — Webhook Processado Sem Bloquear a Chamada do Provedor

O processamento de um webhook (validação, dedupe, transição, chamadas outbound a `Billing Service`/`Notification Service`) deve responder ao provedor dentro de um tempo curto\* (assumido, ver Valores Assumidos) — provedores de pagamento tipicamente reenviam um webhook se não receberem `200 OK` a tempo, o que poderia gerar processamento redundante (mitigado por BD-10, mas evitável reduzindo latência de resposta).

---

## Consistência e Integridade

### RNF-03 — Precisão Decimal Obrigatória em Toda Camada

Nenhum cálculo financeiro (`amount`) usa `float`, em nenhuma camada — banco (`NUMERIC`), aplicação (tipo decimal da linguagem), serialização (JSON como string ou número sem perda de precisão, decisão de serialização específica na implementação). BD-05.

### RNF-04 — Transição de Status Sempre Atômica com Histórico

Toda atualização de `status` de um Payment e o registro de histórico correspondente ocorrem na mesma transação de banco — nunca uma sem a outra, mesmo sob falha parcial. Ver `08-aggregates.md`, invariante 6.

---

## Segurança e Privacidade

### RNF-05 — Autenticação/Autorização Delegadas, Sem Exceção (Exceto Webhook)

Toda rota (exceto `/health` e o próprio webhook, `POST /v1/payments/webhooks/{provider}`) exige JWT válido emitido por `auth-service`; toda operação de escrita exige o Perfil específico (`PAYMENT_CREATE`/`PAYMENT_CANCEL`/`PAYMENT_REFUND`), nunca inferido de `PAYMENT_READ`. BD-04. O webhook usa mecanismo de autenticidade próprio do provedor, não JWT — ver RNF-06 e Hotspot H02.

### RNF-06 — Webhook Nunca Confia Só no Identificador Recebido

Todo webhook é validado quanto à autenticidade (assinatura/segredo do provedor) antes de qualquer processamento — nunca localizar e atualizar um Payment com base apenas no `providerPaymentId` informado, sem essa validação prévia (seção 18 do documento funcional, textual). Hotspot H02 (mecanismo exato).

### RNF-07 — Nenhum Dado Sensível em Log ou Armazenamento

JWT completo, `client_secret`, senha, chave privada, CVV, senha bancária, credencial de banco e dado bancário completo nunca aparecem em log, auditoria ou qualquer tabela deste serviço, sob nenhuma circunstância — mesmo sob pico de volume. BD-15, BD-18.

---

## Disponibilidade e Infraestrutura

### RNF-08 — Infraestrutura MVP: Instância Única, Sem Desvio do Padrão Organizacional

PostgreSQL em instância única, sem cluster/réplica/backup automatizado inicial — adoção direta do padrão organizacional (`padrao-desenvolvimento.md`, seção 8), sem nenhum desvio (mesma decisão de `billing-service`, diferente de `storage-service`, que optou por backup desde o MVP por natureza do próprio domínio). ADR-007.

### RNF-09 — Tensão Registrada: Comunicação HTTP Síncrona Sem Fila

**Desvio explícito do padrão organizacional** (`padrao-desenvolvimento.md`, seção 2 — RabbitMQ como padrão para comunicação assíncrona): este serviço se comunica com `Billing Service`/`Person Service`/`Notification Service`/`Payment Provider` via HTTP síncrono no MVP (BD-14, ADR-010). Consequência aceita: indisponibilidade momentânea de qualquer um desses serviços externos pode falhar uma operação que dependeria deles, sem o amortecimento natural de uma fila — mitigação nesta versão é reprocessamento/retry pelo próprio chamador, não uma garantia interna deste serviço.

---

## Volumetria (Valores Assumidos)

### RNF-10 — Nenhuma Meta de Volume Fixada pelo Usuário

O documento funcional fornecido não especifica volume esperado de pagamentos/dia, nem SLA de latência — nenhuma meta numérica é fixada neste documento; revisar assim que houver dado real de volume (mesmo critério de `billing-service`/`person-service`/`storage-service`).

---

## Observabilidade

### RNF-11 — Logs Estruturados com Correlação

Logs em formato JSON estruturado (`padrao-desenvolvimento.md`, seção 7.2), incluindo `paymentId`, `billingId`, `provider`, `providerPaymentId`, `status`, `operation`, `correlationId` — nunca dado sensível (RNF-07). ADR-009. Correlation ID propagado para `Billing Service`, `Payment Provider` e `Notification Service` (BD-19).

---

## Segurança e Privacidade (adicionado)

### RNF-12 — Nunca Armazenar Dado Financeiro de Destino

Nenhuma chave Pix, conta bancária, agência, número de conta ou dado de cartão é persistida por este serviço, em nenhuma tabela — nem sequer transitoriamente em memória além do escopo estritamente necessário para executar a operação em curso (BD-16). A resolução desse dado é responsabilidade exclusiva do `Person Service`. Mesma restrição já registrada por `billing-service` (RNF-11 daquele serviço) para o lado da obrigação — aqui reforçada do lado da execução.
