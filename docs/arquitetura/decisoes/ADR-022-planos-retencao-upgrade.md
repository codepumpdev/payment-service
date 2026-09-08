# ADR-022 — Plano, Retenção e Expurgo (Aplicação Alvo)

- **Status:** Aceita — **reescrita em 2026-09-08** (a §26 do padrão foi reescrita em 2026-09-06; esta adoção local acompanhou)
- **Data:** 2026-08-15 (reescrita em 2026-09-08)
- **Origem:** `padrao-desenvolvimento.md` §26; `auth-service` ADR-034; `billing-service` ADR-025/ADR-026; `codepump-lib` ADR-012/ADR-013

> **O texto anterior desta ADR descrevia o modelo de 2026-08-15** — `FREE`/`PRO`/`MAX`,
> `PAYMENT` como recurso externo booleano numa lista do plano, `payment.maxRecords` na
> configuração local, `GET /plans` e upgrade empurrado por endpoint. Ele **não vale mais**.
> O desfecho de cada uma das 9 decisões originais está na tabela **Histórico**, no fim.
>
> Esta foi a ADR **mais afetada** das aplicações alvo, porque o mecanismo em que a decisão
> central dela se apoiava — a lista de recursos externos da §26.10 — deixou de existir.

## Contexto

O `payment-service` é uma **aplicação alvo**: recebe operações **em nome de** um usuário no
modelo de **dois cabeçalhos** (§9.4 — `SERVICE JWT` no `Authorization` + `USER JWT` no
`X-User`) e aplica ao domínio de Pagamentos o que o plano do titular concede.

Diferente dos demais alvos, aqui a regra central não é contar registros: é decidir **se o
plano dá direito a pagar**, antes de qualquer movimentação financeira. Era isso que a
versão anterior expressava com um recurso externo booleano.

**O catálogo novo é quantitativo** (`auth-service` ADR-034, decisão 14): ele tem `quantity`
por serviço e um `extras` opaco, e **não** tem a lista de recursos externos que a §26.10
tinha. A decisão central desta ADR precisou ser reexpressa — e a novidade é que ela ficou
mais simples, não menos.

Duas tensões com decisões vigentes deste serviço continuam onde estavam:

1. **ADR-006** decidiu que um Payment é imutável e nunca removido; **ADR-021** já abriu a
   primeira exceção de remoção física (expurgo de `PENDING` órfãos). A retenção de plano
   amplia esse caminho. Esta ADR **emenda** o ADR-006 e **estende** o `/internal/purge`,
   nunca cria endpoint separado.
2. **BD-16** decidiu que este serviço **não persiste** dado financeiro de destino. As
   colunas de titular não são dado de destino — são escopo de plano. A tensão continua
   anotada como Hotspot.

## Decisão

### 1. O plano é opaco, e a fatia deste serviço É o direito de pagar (§26.1/§26.2/§26.3)

Este serviço **não conhece nome de plano nenhum**. Da **raiz** do `USER JWT` lê o sujeito, o
plano (`plan`) e o `accessUntil`; pede ao `planresolver` a fatia de `payment-service`; e lê
dela o `quantity`.

**O recurso `PAYMENT` virou a própria fatia**, e os dois erros continuam distintos:

```text
quantity: 0      →  o plano não dá direito a pagar     →  403 RECURSO_NAO_PERMITIDO_NO_PLANO
quantity: N      →  N pagamentos; o N+1 é recusado     →  403 LIMITE_PLANO_ATINGIDO
quantity: null   →  sem limite
```

**Zero não é limite atingido, e por isso o código de erro não é o mesmo.** *"Você não
contratou isto"* e *"você já usou tudo o que contratou"* levam o cliente a ações diferentes
— uma é upgrade, a outra é esperar o próximo ciclo. Era essa distinção que a decisão
original protegia com um recurso booleano, e ela sobrevive à mudança de forma.

Um plano cuja fatia **não alcança** este serviço é tratado como `quantity: 0`: não alcançar
e não dar direito são a mesma coisa aqui.

A verificação continua **prioritária sobre o limite** e continua acontecendo **antes de
qualquer efeito** — antes da validação de cobrança (BD-11), antes de obter o recebedor
(BD-16), antes de falar com o provedor (BD-13). Nenhum Payment é criado, nenhuma chamada
externa é feita. Falha barata e sem rastro.

Erro ao resolver a fatia é **recusa**, nunca "ilimitado" (`codepump-lib` ADR-013, decisão
7). Num serviço que move dinheiro, isso não é escolha de estilo.

### 2. A retenção NÃO vem do catálogo (§26.6)

`retentionDays` continua na configuração **deste serviço**. O catálogo é quantitativo e
comercial; por quanto tempo um Payment fica é política do domínio.

### 3. Titular — `payments.owner_user_id` e `owner_organization_id`

O titular é o sujeito do token: a **Organização** quando o token a traz, o usuário caso
contrário (`auth-service` ADR-034, decisão 1). Referências **opacas** (§8.2), sem FK.

**Não é dado financeiro de destino** — BD-16 preservada. É escopo de plano: contagem de
limite e escopo de retenção. Mantido mínimo, só o identificador, sem nome, documento ou
contato. Ambas `NULL` fora de contexto de usuário.

### 4. Limite de registros (§26.5)

Passada a verificação da decisão 1, e com `quantity` finito: conta os Payments do titular
excluindo os já expurgados, e recusa com `403 LIMITE_PLANO_ATINGIDO` quando a contagem
alcançou o teto.

Na versão anterior esta regra era quase inerte: nenhum Payment `FREE` era criado, então
nada havia a contar. Com o catálogo quantitativo, um plano com `quantity: 5` é uma
configuração perfeitamente normal — **a regra deixou de ser hipotética**, e passa a exigir
cobertura de teste real.

### 5. Retenção — `payments.purge_at` (§26.6)

`purge_at` fica **somente** na raiz `payments`. As tabelas relacionadas
(`payment_status_history`, `payment_provider_events`) não têm `purge_at`.

`purge_at = created_at + retentionDays` na criação em contexto de usuário. Pela mesma razão
da decisão 4, esta regra também deixou de ser inerte.

### 6. Acesso vencido NÃO suspende o pagamento (§26.7) — a exceção nomeada

```text
cliente inadimplente tenta pagar  →  bloqueado por estar inadimplente
                                  →  não consegue sair da inadimplência
```

A §26.7 nomeia este serviço como **exceção**: o fluxo de pagamento nunca é suspenso. Criar
Payment é ação do cliente, e mesmo assim não para quando `accessUntil` está no passado.

**E o limite quantitativo não recria o impasse por outro caminho**, por uma razão que já
estava no desenho: a fatura da assinatura é cobrada **sistema a sistema**, sem `X-User`, e a
§26.5 põe a operação M2M pura fora de limite e de retenção. O pagamento que tira o cliente
da inadimplência nunca passa pela contagem.

Para um pagamento iniciado pelo cliente enquanto ele está vencido, vale a exceção acima: o
acesso vencido não o bloqueia.

**As duas regras juntas fecham o impasse pelos dois lados**, e é preciso que estejam
escritas juntas — cada uma sozinha deixaria uma fresta.

### 7. Expurgo — `POST /internal/purge` estendido (§26.8/§26.9)

O endpoint **já existe** (ADR-021). Ele passa a ter **três** gatilhos:

| motivo | gatilho |
|---|---|
| Órfãos `PENDING` (ADR-021, inalterado) | lógica original |
| Retenção do plano | `payments.purge_at <= now()` |
| Inadimplência | titular na lista de `GET /internal/defaulters` do `billing-service` há mais que a retenção local (**12 meses**) |

**Cada execução reconcilia:** marca quem entrou na lista e passou do prazo, **limpa** a
marca de quem saiu dela, e apaga o que venceu — é assim que o pagamento desfaz a marca sem
evento nenhum.

**Se o `billing-service` não responder:** os dois primeiros motivos executam normalmente, a
falha do terceiro é registrada, e **nenhuma marca é limpa**.

O expurgo remove o registro **inteiro** quando a retenção vence, e não o edita: o ADR-006
continua valendo — Payment é imutável. É a **emenda ao ADR-006**, que agora cobre três
gatilhos em vez de um. Continua disparado pela **mesma** Tarefa Agendada
`payment-orphan-purge`.

### 8. Este serviço não expõe rota de plano (§26.13)

Não há `GET /plans` nem `/config/plans`. O catálogo é do `billing-service`, e publicá-lo
aqui criaria uma segunda verdade sobre preço e direito. Administra-se lá, em
`PUT /v1/admin/plans/{planId}`.

### 9. Fronteira (§26.11)

Este serviço **aplica** direito, limite, retenção e expurgo; `auth-service` e
`billing-service` **fornecem** o contexto. Nenhum deles aplica essas regras.

## Consequências

### Positivas

- A regra comercial mais importante deste serviço — **quem pode pagar** — continua aplicada
  na fronteira certa, e ficou expressa por um número em vez de uma lista.
- A verificação continua sendo barreira **antes** de qualquer efeito colateral: falha
  barata, sem rastro, sem chamada externa.
- Os dois erros continuam distintos, apesar de virem do mesmo campo. É o ponto que mais
  facilmente se perderia na tradução, e é o que a decisão 1 protege.
- Um plano novo — inclusive um que permita pagar com teto — é edição de catálogo, sem
  deploy aqui.
- O expurgo reaproveita `/internal/purge` + a Tarefa Agendada já existentes.

### Negativas / Hotspots

- **Remoção física agora tem três motivos** (emenda alargada ao ADR-006). Qualquer outro
  alargamento é decisão separada.
- **Limite e retenção deixaram de ser inertes.** Na versão anterior nenhum Payment `FREE`
  existia e as duas regras nunca rodavam; com o catálogo quantitativo elas rodam, e
  precisam de teste real. É a mudança de maior efeito prático desta reescrita.
- **`owner_*` vs. BD-16 (Hotspot\*):** continua sendo a primeira identidade de usuário
  persistida por este serviço. Mantida mínima; confirmar com o negócio se persistir o
  titular é aceitável, ou se contagem e retenção deveriam ser resolvidas sem gravá-lo.
- **`retentionDays` continua valor assumido\***, e os 12 meses da inadimplência também\*.
- **Dependência nova de partida:** sem o catálogo acessível o `planresolver` não resolve, e
  o pagamento em contexto de usuário é **recusado**. É a postura correta aqui, e é também a
  que mais dói: uma indisponibilidade do catálogo para a cobrança iniciada pelo cliente.
  A cobrança M2M da assinatura não passa por essa verificação.

## Critérios para reavaliar

- Se um plano vier a permitir pagar com teto por janela de tempo (N por mês), a contagem da
  decisão 4 precisa da janela — hoje ela é total.
- Se persistir o titular se mostrar em tensão com BD-16 na prática.
- Se a exceção da decisão 6 alguma vez for questionada, o impasse descrito ali é o que
  precisa ser respondido primeiro — os dois lados, não um.

## O que o código já tem

Este serviço **não tem uma linha de Go**. Não há divergência a registrar entre ADR e código,
e não há resíduo a remover — diferente de `person-service` e `storage-service`, que ainda
carregam o `POST /internal/users/{userId}/plan` da decisão que morreu.

Quando a Implementação começar, esta ADR é a especificação; a versão anterior não é.

## Histórico — o que esta ADR decidia até 2026-09-06

A versão original (2026-08-15) adotava a §26 na forma que ela tinha então: planos nomeados,
`PAYMENT` como recurso externo booleano na lista da §26.10, `payment.maxRecords` na
configuração local, e upgrade como chamada. O desfecho de cada decisão:

| decisão original | desfecho |
|---|---|
| 1. Planos `FREE`/`PRO`/`MAX` | **Morreu.** Os três nomes saíram |
| 2. Recurso externo `PAYMENT` booleano | **Mudou de forma, não de efeito.** Virou `quantity: 0` na fatia; os dois códigos de erro continuam distintos |
| 3 / 3.1. Titular — `payments.owner_user_id` | **Ficou**, e ganhou `owner_organization_id` |
| 4. Limite de registros | **Ficou a mecânica**; mudou a origem do número, e deixou de ser inerte |
| 5. Retenção — `payments.purge_at` | **Ficou inteira**, e também deixou de ser inerte |
| 6. Upgrade — `POST /internal/users/{userId}/plan` | **Morreu.** A reconciliação do expurgo substitui o aviso empurrado |
| 7. Expurgo | **Ficou**, e ganhou o motivo de inadimplência — 12 meses |
| 8. `GET /plans` e `/config/plans` | **Morreram** |
| 9. Fronteira | **Ficou inteira** |

O texto integral da versão anterior está no histórico do repositório; o que dela sobreviveu
está reescrito acima, e o que morreu está nomeado nesta tabela.

## Nota de integração

- `padrao-desenvolvimento.md` §9.3/§9.4 (dois cabeçalhos), §26 inteira, §26.7 (este serviço
  como exceção ao modo somente leitura), §26.14 (mapa do que deixou de existir).
- `auth-service` ADR-034 (plano do sujeito na raiz; catálogo quantitativo, decisão 14; a
  Organização vence).
- `billing-service` ADR-025 (ciclo de vida do direito de uso, e os 12 meses) e ADR-026 (dono
  do catálogo); `GET /internal/defaulters`.
- `codepump-lib` ADR-012 (o `plan` por perfil saiu do token) e ADR-013 (`planresolver`).
- `dominio/03-business-decisions.md` — BD-21 (direito de pagar/limite/retenção/expurgo).
- `modelo-dados/19-data-model.md` — colunas de titular e `purge_at`.
- `contratos/17-api-contracts.md` — a seção de planos precisa ser ajustada: ela ainda
  documenta `GET /plans`, `/config/plans` e `POST /internal/users/{userId}/plan`, que a
  decisão 8 elimina, e ainda descreve o gating por recurso booleano.
- `dominio/04-ubiquitous-language.md` — Plano/Titular/`purgeAt`/Expurgo.
- `arquitetura/decisoes/ADR-006-payment-imutavel-sem-remocao.md` — emenda, agora com três
  motivos.
- `arquitetura/decisoes/ADR-021-expurgo-pagamentos-pendentes-orfaos.md` — o `/internal/purge`
  com três motivos, distinguidos na auditoria.
- `requisitos/10-functional-requirements.md` (RF-11).
- `scheduler-service` — a Tarefa Agendada `payment-orphan-purge` cobre os três motivos;
  nenhuma tarefa nova.
