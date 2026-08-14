# ADR-019 — Padrão de Health Check, Readiness Check e Identificação de Build (Adoção do Padrão Organizacional)

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

Até esta ADR, `payment-service` nunca formalizou nenhum contrato de health-check: `17-api-contracts.md` cita `GET /health` apenas como exceção de versionamento (ADR-005), sem nunca ter especificado formato de resposta, códigos HTTP, o que exatamente é verificado, nem qualquer noção de *readiness* (prontidão para operar, distinta de "processo vivo"). Não existe, até esta ADR, nenhum endpoint `/ready`, nenhuma decisão de negócio (`03-business-decisions.md`) sobre monitoração, e nenhum bounded context de monitoração — mesmo perfil de `person-service` (ADR-014 daquele serviço) e `billing-service` (ADR-018 daquele serviço).

Em 2026-08-13, `codepump/codepump/docs/padrao-desenvolvimento.md` (seção 12) formalizou um padrão organizacional único, obrigatório para todo serviço já documentado (incluindo `payment-service`, citado nominalmente) e todo novo serviço futuro, cobrindo três pontos: geração automática de `build.properties` no build, o contrato de `GET /health` (liveness + identificação de build) e o contrato de `GET /ready` (readiness + dependências obrigatórias). Como este serviço nunca tinha nenhuma implementação individual de `/health` a substituir, esta ADR não emenda nenhum texto anterior sobre o assunto — apenas adota o padrão pela primeira vez.

**Nota de conformidade — Tarefas Agendadas (seção 13):** diferente de `billing-service` (que precisou migrar uma goroutine agendada para o `scheduler-service`, ADR-019 daquele serviço), `payment-service` **não tem nenhum job periódico interno** nesta versão — já registrado explicitamente em `contratos/18-event-contracts.md`, seção "Jobs Internos — Não São Eventos de Domínio", e em `arquitetura/13-architecture.md`, seção "Job Interno": toda transição de status é reativa (criação via HTTP ou webhook do provedor). Este serviço já está em conformidade com o padrão organizacional da seção 13 sem exigir nenhuma migração — não há nada a expor sob `/internal/*` para o `scheduler-service` chamar.

## Decisão

Este serviço adota integralmente o padrão da seção 12 de `padrao-desenvolvimento.md`, com as dependências concretas de `payment-service` determinadas a partir do restante desta documentação (ver "Dependências de `payment-service` para `/ready`", abaixo).

### 1. `build.properties`

Gerado automaticamente durante o build (nunca manualmente), na raiz do artefato, pelo pipeline de CI/CD (etapa 13, hoje `Pendente` — ver `roadmap.md`):

```properties
branch=main
commit=ba996ad8715
buildDate=2026-08-13T14:30:00-03:00
```

`branch`/`commit` vêm do processo de CI/CD (ou do build local); `buildDate` é o instante real de construção do artefato (ISO 8601 com timezone) — nunca o horário de inicialização do container. Um redeploy do mesmo artefato, sem novo build, nunca muda `buildDate`. Lido uma única vez na inicialização do processo Go, mantido em memória (mesmo princípio já usado para segredos do OpenBao — ADR-008).

### 2. `GET /health` — Liveness e Identificação de Build

Verifica **somente** se o próprio processo Go está de pé — nunca consulta PostgreSQL, OpenBao, `auth-service`, `Billing Service`, `Person Service`, `Notification Service` ou `Payment Provider`. Sem autenticação; fora do prefixo `/v1` (exceção deliberada já registrada em ADR-005/`17-api-contracts.md`, mesma convenção de mercado de health-check para orquestradores).

**Response — 200 OK** (processo consegue responder):
```json
{
  "status": "UP",
  "branch": "main",
  "commit": "ba996ad8715",
  "buildDate": "2026-08-13T14:30:00-03:00"
}
```

**Response — 503 Service Unavailable** (processo não consegue responder normalmente). Os três campos de build vêm de `build.properties` (seção 1), lidos uma vez na inicialização.

### 3. `GET /ready` — Readiness e Dependências Obrigatórias de `payment-service`

Verifica apenas as dependências que **este serviço especificamente** precisa para operar — nunca dependências de outro serviço que não afetam este, e nunca `/ready` de outro serviço (só `/health` dele, para evitar dependência circular).

**Response — 200 OK** (toda dependência obrigatória disponível):
~~```json
{
  "status": "READY",
  "checks": {
    "database": "UP",
    "auth-service": "UP"
  }
}
```~~

**Response — 503 Service Unavailable** (`status: "NOT_READY"`, cada dependência indisponível marcada `"DOWN"`):
~~```json
{
  "status": "NOT_READY",
  "checks": {
    "database": "DOWN",
    "auth-service": "UP"
  }
}
```~~

**Atualização (2026-08-13):** o formato `checks` (valor string) é substituído pelo formato abaixo, que complementa cada verificação com `responseTime` (ms, sem unidade) — permite identificar degradação de desempenho, não só indisponibilidade (`padrao-desenvolvimento.md`, seção 12.3).

**Response — 200 OK** (toda dependência obrigatória disponível):
```json
{
  "status": "READY",
  "responseTime": 31,
  "dependencies": {
    "database": { "status": "UP", "responseTime": 8 },
    "auth-service": { "status": "UP", "responseTime": 22 }
  }
}
```

**Response — 503 Service Unavailable** (`status: "NOT_READY"`; a dependência que não respondeu dentro do timeout vem `"DOWN"` com `responseTime: null` e `error: "TIMEOUT"`):
```json
{
  "status": "NOT_READY",
  "responseTime": 5000,
  "dependencies": {
    "database": { "status": "DOWN", "responseTime": null, "error": "TIMEOUT" },
    "auth-service": { "status": "UP", "responseTime": 19 }
  }
}
```

### Uso de `responseTime` para Degradação

O `responseTime` de cada dependência (e o do nível raiz) é o dado de entrada consumido pelo `alert-service` para detectar degradação de desempenho, não apenas indisponibilidade (`padrao-desenvolvimento.md`, seção 12.5).

### Dependências de `payment-service` para `/ready`

| Dependência | Verificada no `/ready`? | Justificativa |
|---|---|---|
| PostgreSQL (banco próprio `payment` — ADR-018) | **Sim, obrigatória** | Toda operação de escrita e leitura deste serviço (criação, consulta, aplicação de resultado de webhook, histórico, auditoria) depende do banco (ADR-007). Verificação por conectividade simples (`SELECT 1`), nunca uma consulta de negócio. |
| `auth-service` | **Sim, obrigatória** | Toda chamada a este serviço (exceto o webhook, BD-04) exige um JWT válido, validado contra a chave pública de `auth-service` (`GET /v1/auth/public-key`, ADR-001, BD-04) — sem essa validação, nenhum endpoint de negócio pode ser autorizado. Mesmo raciocínio já formalizado por `person-service` (ADR-014) e `billing-service` (ADR-018 daquele serviço): a chave pública em cache é reatualizada sempre que um `kid` desconhecido aparece, e a própria inicialização do processo depende de alcançar `auth-service` para obter a primeira chave. Verificado via `GET /health` de `auth-service` (nunca `/ready` dele, seção 12.3). |
| `Billing Service` | **Não** *(ver Hotspot H04, abaixo)* | Consulta síncrona e **bloqueante** (`GET /v1/billings/{id}`, BD-11) — sem ela, nenhum Payment pode ser criado (`13-architecture.md`, `03-business-decisions.md` BD-01: "se aquele serviço estiver indisponível, nenhum Payment pode ser criado") — mas essa dependência é restrita ao único endpoint de criação (`POST /v1/payments`, RF-01); `GET /v1/payments/{id}`, `GET /v1/payments?billingId=...` e o webhook do provedor (Fluxo 5/6) continuam funcionando normalmente sem `Billing Service` disponível. Classificar `Billing Service` como obrigatória no `/ready` tornaria o serviço inteiro `NOT_READY` (e potencialmente fora de rotação de balanceamento, `padrao-desenvolvimento.md` seção 14.5) por uma indisponibilidade que afeta só um subconjunto dos endpoints — mesma situação estrutural já registrada por `person-service` em relação a `storage-service` (Hotspot H05 daquele serviço). O informe de resultado (Fluxo 7) ao `Billing Service`, por outro lado, é não-bloqueante (ocorre após o Payment já estar `APPROVED`/`REJECTED` de forma definitiva) e não pesa nesta classificação. `Billing Service` já expõe `GET /health` oficial (`billing-service`, ADR-018 daquele serviço) — o mecanismo de verificação existiria, se a decisão fosse incluí-la. |
| `Person Service` | **Não** *(mesmo raciocínio do Hotspot H04, restrição ainda mais estreita)* | Consulta síncrona e bloqueante (`GET /v1/persons/{personId}/receiving-accounts`\*, BD-16) — mas restrita a uma fração ainda menor do serviço: só ocorre dentro do endpoint de criação (`POST /v1/payments`), e só quando `type = PAY` (Fluxo 4). Pagamentos `RECEIVE`, toda consulta, e o webhook do provedor não dependem de `Person Service` em nenhum momento. Mesma lógica do Hotspot H04, aplicada com margem ainda maior para excluir. `Person Service` já expõe `GET /health` oficial (`person-service`, ADR-014 daquele serviço). |
| `Payment Provider` | **Não** | Duas razões independentes, cada uma suficiente por si só: (1) a regra organizacional (seção 12.3) só permite verificar um serviço externo crítico no `/ready` **se existir um endpoint de health-check oficial documentado** daquele provedor — o provedor real ainda não foi escolhido (Hotspot H01), então nenhum mecanismo oficial existe hoje para verificar; (2) mesmo quando o provedor for escolhido, a regra organizacional proíbe explicitamente executar uma operação de negócio real (uma transação de pagamento) só para testar disponibilidade — o envio da operação (BD-13) só acontece dentro do fluxo real de criação, nunca como sondagem de saúde. |
| `Notification Service` | **Não** | A chamada a `Notification Service` (BD-01, seção 27 do documento funcional) acontece **fora** da transação de banco que originou a mudança de status, depois de o Payment já estar persistido corretamente (`13-architecture.md`, "Comunicação HTTP Outbound") — uma falha nessa chamada não desfaz nem impede a operação principal, mesmo padrão de "chamada fire-and-forget, não bloqueante" já usado por `auth-service` (ADR-023) e reaproveitado por `billing-service` (ADR-018 daquele serviço) para excluir `Notification Service` de seus próprios `/ready`. Reaproveitamento direto do precedente, não um novo Hotspot. |
| OpenBao (ADR-008) | **Não** | Mesmo raciocínio já formalizado por `auth-service` (ADR-023, Hotspot H16) e reaproveitado por `person-service` (ADR-014) e `billing-service` (ADR-018): a senha de conexão do PostgreSQL e as credenciais M2M/de provedor são lidas do OpenBao **apenas na inicialização** do processo e mantidas em memória durante toda a execução (`arquitetura/15-infrastructure.md`) — uma indisponibilidade do OpenBao **depois** da inicialização bem-sucedida não impede este serviço de continuar operando normalmente. Reaproveitamento direto do precedente, não um novo Hotspot. |
| RabbitMQ | **N/A** | `payment-service` não usa mensageria (BD-14, ADR-010 — desvio deliberado do padrão organizacional) — linha omitida do `checks`, nunca incluída como `"DOWN"` fixo. |

### 4. Diferença entre `/health` e `/ready` (payment-service)

```text
/health                          /ready
  |                                 |
  +-- processo Go vivo?             +-- pronto para operar?
  +-- branch/commit/buildDate       +-- database (PostgreSQL "payment")
  |                                 +-- auth-service (via GET /health dele)
  +-- NUNCA verifica database,      +-- NUNCA verifica Billing Service (H04),
      auth-service, Billing            Person Service (H04, restrição maior),
      Service, Person Service,          Payment Provider (H01, sem mecanismo
      Payment Provider, Notification    oficial + proibição de transação real),
      Service ou OpenBao                Notification Service (não-bloqueante)
                                         ou OpenBao (precedente H16)
```

## Consequências

### Positivas

- Formaliza um contrato de `/health` que nunca havia sido especificado (apenas citado como exceção de versionamento) — elimina ambiguidade de implementação.
- Introduz `/ready`, inexistente até esta ADR, dando às aplicações/orquestradores um sinal de prontidão real, distinto de "processo vivo".
- A tabela de dependências deixa por escrito, pela primeira vez, por que `Billing Service` e `Person Service` — apesar de ambos terem uma chamada síncrona e **bloqueante** real (BD-11, BD-16) — não são tratados como obrigatórios: a chamada bloqueante existe só dentro do endpoint de criação (e, para `Person Service`, só dentro de um subtipo desse endpoint), não em todo o serviço.
- Identificação de build (`branch`/`commit`/`buildDate`) resolve uma necessidade operacional que este serviço nunca tinha formalizado antes.
- Confirma, sem exigir nenhuma mudança, que este serviço já está em conformidade com o padrão organizacional de Tarefas Agendadas (seção 13) — nenhum job interno a migrar.

### Negativas

- A classificação de `Billing Service`/`Person Service` como não-obrigatórios para `/ready` depende de uma leitura específica da regra organizacional ("se for dependência obrigatória") aplicada a uma dependência que é bloqueante só para uma fração dos endpoints deste serviço — mesmo cenário que a seção 12.3 de `padrao-desenvolvimento.md` não cobre explicitamente (a tabela de regras trata dependências como obrigatórias ou não para o serviço inteiro, não por endpoint), já identificado por `person-service` (Hotspot H05 daquele serviço). Uma reavaliação futura do padrão organizacional poderia inverter essa conclusão.
- `/ready` com duas dependências (`database`, `auth-service`) é propositalmente mínimo — reflete a realidade real deste serviço, não uma implementação incompleta.
- A não-inclusão de `Payment Provider` no `/ready` depende, em parte, de o provedor real ainda não ter sido escolhido (Hotspot H01) — quando escolhido, se o provedor expuser um endpoint de health-check oficial, a classificação precisa ser revisitada à luz do novo dado disponível, não presumida como permanente.

## Critérios para reavaliar

- Se `payment-service` passar a depender de RabbitMQ (mudança de arquitetura não prevista hoje — ADR-010, desvio deliberado), adicionar `rabbitmq` a `checks`.
- Se o uso do OpenBao por este serviço evoluir para segredos dinâmicos (credenciais de curta duração, obtidas periodicamente em vez de uma única vez no startup), reavaliar se OpenBao passa a ser dependência obrigatória de `/ready`.
- Quando o `Payment Provider` real for escolhido (Hotspot H01) e expuser um endpoint de health-check oficial, reavaliar se deve entrar em `/ready` — mesmo que o envio da operação continue restrito ao fluxo de criação, a regra organizacional (seção 12.3) permite (não exige) verificar dependências não-obrigatórias quando um mecanismo adequado existir; decisão a tomar naquele momento.
- Se algum outro fluxo além da criação (RF-01) passar a depender de `Billing Service`/`Person Service`, ou se o volume de criações bloqueadas por indisponibilidade desses serviços se mostrar operacionalmente relevante, reavaliar a inclusão de ambos em `/ready` (ver Hotspot H04).

## Hotspot H04 — `Billing Service` (e, com restrição ainda maior, `Person Service`) são dependências obrigatórias do `/ready` de `payment-service`?

*(Novo — não resolvido por nenhuma decisão anterior; a regra organizacional, seção 12.3, não distingue explicitamente "dependência bloqueante para todo o serviço" de "dependência bloqueante só para um subconjunto de endpoints", mesma lacuna já identificada por `person-service`, Hotspot H05 daquele serviço.)* Esta ADR decide, com a justificativa acima, **não** incluir `Billing Service` nem `Person Service` no `/ready` — mas essa é uma interpretação desta equipe da regra organizacional, não uma resposta explícita dela. Diferente do caso de `Notification Service`/OpenBao (chamadas/leituras estruturalmente não-bloqueantes ou restritas ao startup), aqui a dependência é usada em tempo de requisição, de forma síncrona e bloqueante (BD-11, BD-16), só que restrita a um único endpoint (`Billing Service`) ou a um subtipo de um único endpoint (`Person Service`, só `PAY`), em vez de afetar o serviço inteiro. Fica registrado como Hotspot para eventual alinhamento entre serviços da organização (o mesmo padrão de interpretação já usado por `person-service`, H05, é reaproveitado aqui, mas cada novo caso análogo continua exigindo registro próprio até que a organização decida formalizar um critério único na seção 12.3) e para revisão caso o padrão de uso de `Billing Service`/`Person Service` por este serviço se amplie (ver Critérios para reavaliar). Não bloqueia a Implementação (etapa 9) — o comportamento de erro do próprio endpoint de criação (`404`/`409`/`422`, `17-api-contracts.md` seção 1) já cobre a indisponibilidade dessas dependências no momento do uso, independentemente da resposta de `/ready`.

## Nota de integração

* `dominio/03-business-decisions.md` — nova referência cruzada (este serviço não tinha nenhuma BD sobre health-check a emendar).
* `dominio/05-bounded-contexts.md` — não modificado por esta ADR: este serviço nunca teve um comando "Consultar Saúde do Serviço" nem um bounded context de Monitoração a desdobrar; `/health`/`/ready` ficam documentados em `13-architecture.md` e `17-api-contracts.md`.
* `arquitetura/13-architecture.md` — componente Payment API atualizado.
* `contratos/17-api-contracts.md` — nova seção (`GET /health`, `GET /ready`), nova tabela "Resumo de Rotas".
* `contratos/18-event-contracts.md` — nota confirmando conformidade com a seção 13 (nenhum job periódico interno existe neste serviço, nada a migrar).
* `arquitetura/15-infrastructure.md` — nova subseção sobre geração de `build.properties`.
* `dominio/01-event-storming-big-picture.md` — novo Hotspot H04 adicionado à tabela de Hotspots.
* `codepump/codepump/docs/padrao-desenvolvimento.md` — seção 12, origem deste padrão (seção 13 confirmada como já cumprida, sem migração necessária).
* `codepump/codepump/docs/padrao-desenvolvimento.md` — atualização de 2026-08-13 da seção 12.3 (formato de `/ready`: `checks` com valor string → `dependencies`, cada uma com `responseTime` em ms, mais `responseTime` no nível raiz); o `/ready` deste serviço foi migrado para o novo formato nesta atualização.
* `roadmap.md`/`roadmap.html` — nova entrada em Concluído.
