# ADR-020 — API de Configuração (`GET /admin/config`, Adoção do Padrão Organizacional)

- **Status:** Aceita
- **Data:** 2026-08-14 · **Reescrita:** 2026-08-19

## Contexto

Até esta ADR, `payment-service` só expunha configuração efetiva de forma legível por máquina, via
`GET /props` — um JSON de diagnóstico restrito ao Perfil `ADMIN`. Não havia superfície para um
operador humano consultar a configuração administrável do serviço sem ler `/props` cru,
variável de ambiente ou `compose.yaml`.

A versão anterior desta ADR resolvia isso com uma **tela própria** em `GET /admin/config`,
renderizada pelo próprio app Go — era o que o padrão organizacional exigia à época.

**Esse padrão foi revisto em 2026-08-19.** Cada serviço renderizar a própria tela significava
onze implementações de sessão administrativa, layout, navegação e formulário — tudo o que o
`admin-console-service` já tem —, e obrigava o operador a conhecer a URL de cada serviço para
administrá-lo. A UI de configuração passou a viver num lugar só, o console, e o que cabe a cada
serviço é um endpoint JSON de leitura.

## Decisão

`payment-service` adota a seção 23 de `padrao-desenvolvimento.md` /
`padroes-implementacao/padrao-api-config.md`, provendo **`GET /admin/config` como API de
leitura**. O serviço **não tem front-end**.

### 1. Endpoint JSON, nunca tela

`GET /admin/config` devolve JSON. Sem `html/template`, sem HTMX, sem CSS, sem `internal/web/`,
sem `embed` de assets, sem SPA — a questão do framework de front-end deixa de existir neste
serviço porque front-end nenhum existe aqui. A UI correspondente é um módulo do
`admin-console-service`, que consome este endpoint.

### 2. Somente leitura — a escrita é da API administrativa

Nenhum `POST`/`PUT`/`PATCH` em `/admin/config`. Alterar configuração é operação da API
administrativa do próprio serviço, com a validação de negócio dela; este endpoint apenas
**descreve** cada propriedade e aponta, no campo `endpoint`, onde alterá-la. É esse metadado
que permite ao console montar a tela sem conhecer o serviço.

### 3. Protegido pela autenticação administrativa do serviço

Exige JWT válido com o Perfil `ADMIN` na entrada de `profiles` com `app: PAYMENT_SERVICE` — o mesmo
Perfil já exigido pelo `/props`. Nunca acesso anônimo. Falta de Perfil → `403 PERFIL_INSUFICIENTE`.

### 4. Categorias de configuração devolvidas

O endpoint devolve **apenas** as configurações administráveis, com as propriedades somente-leitura relevantes visualmente diferenciadas das editáveis. Componente HTML adequado ao tipo (string→input, number→number, boolean→checkbox/switch, enum→select, URL→url).
- **Aplicação** — `environment` (somente-leitura); identificação de build `branch`/`commit`/`buildDate` (somente-leitura, ADR-019); host/porta do servidor HTTP (somente-leitura, **exige reinicialização**).
- **Banco de dados** — nome do banco lógico `payment` (somente-leitura, ADR-018); parâmetros de pool de conexão, quando expostos (editáveis, **exige reinicialização**); senha de conexão **nunca exibida** (secret — indicador booleano "configurada: sim", ADR-008).
- **Serviços internos** — URLs base de `Billing Service`, `Person Service` e `Notification Service` (editáveis) e seus **timeouts** de chamada HTTP síncrona (editáveis, ADR-010); `client_id` M2M (somente-leitura); `client_secret` M2M **nunca exibido** (secret, OpenBao).
- **Serviços externos** — provedor de pagamento **ativo** escolhido por configuração (enum/select, ADR-015, **exige reinicialização**); URL/endpoint do provedor (editável); timeout da chamada ao provedor (editável); chave de API e segredo de assinatura de webhook do provedor **nunca exibidos** (secrets — indicadores booleanos, ADR-008, Hotspot H01/H02).
- **Mensageria** — host do RabbitMQ e exchange de auditoria `audit.events` (somente-leitura, §17); Publisher Confirms habilitado (somente-leitura); credencial de conexão **nunca exibida** (secret, OpenBao).
- **Operacional** — timeout do Readiness Check (editável); limites de log (10 MB por arquivo, 10 arquivos, 100 MB por aplicação — somente-leitura, padrão organizacional, ADR-009).
- **Retenção / Expurgo (editável — adicionado em 2026-08-14, ADR-021):** `payment.purge.minPendingAgeHours` (padrão `24`) — idade mínima de um Pagamento `PENDING` para ser considerado candidato ao expurgo de órfãos (`POST /internal/purge`), salvaguarda anti-corrida com a criação da Cobrança. Refletido em `GET /props` (`limits`). Alterar aqui muda quais candidatos a próxima execução do expurgo avalia; nunca dispara expurgo por si só (o disparo é do `scheduler-service`).
O efeito de cada alteração é sinalizado como **imediato** (ex.: timeout de chamada outbound) × **exige reinicialização** (ex.: porta HTTP, provedor ativo). Nunca informar "aplicado" sem confirmação real de aplicação pelo serviço.

### 5. Nunca expõe segredos

Segredo aparece com `type: "secret"` e um booleano `configured`, nunca o valor — nem mascarado,
nem parcial. Os segredos deste serviço vivem no OpenBao, são lidos na inicialização e não
transitam por este endpoint. Connection string com credencial é segredo.

### 6. Auditoria é da escrita, não da leitura

A alteração feita pela API administrativa publica o `AuditEvent` canônico da `codepump-lib`
(seção 17) no exchange `audit.events`: `action = UPDATE`, `resource = CONFIG`, e `data` com a
propriedade e os valores anterior e novo — **nunca** valor sensível. Ler `/admin/config` não
gera evento.

### 7. Sem API paralela

Dado de entidade que a tela do console exiba vem das APIs GET padronizadas (seção 20,
`padrao-consultas-filtros.md`). `/admin/config` descreve configuração, não dado de negócio.

## Consequências

### Positivas

- Uma UI de configuração para a plataforma inteira, no console, em vez de onze telas a manter e
  a manter consistentes entre si.
- O serviço fica sem front-end: nenhuma superfície HTML autenticada a mais para defender,
  nenhum asset embutido no binário, nenhuma dependência de template.
- O endpoint é JSON: barato de servir e fácil de testar, ao contrário de uma tela.
- Reforça a garantia já dada pelo OpenBao: o segredo não tem caminho de exposição por aqui.

### Negativas

- Administrar este serviço passa a depender do `admin-console-service` estar no ar e ter o
  módulo correspondente implementado — antes, a tela local funcionava sozinha.
- O metadado por propriedade (`editable`, `endpoint`, `effect`) precisa ser mantido em sincronia
  com as APIs administrativas reais; um `endpoint` desatualizado quebra a tela do console sem
  quebrar teste nenhum deste serviço.

## Critérios para reavaliar

- Se a configuração programável deste serviço crescer, estender as categorias na mesma ADR que
  introduzir a nova configuração, mantendo a marcação de editável e o endpoint de escrita.
- Se algum serviço vier a precisar de operação administrativa sem console disponível (recuperação
  de desastre, por exemplo), reavaliar se um modo de emergência se justifica — hoje não há caso.

## Nota de integração

* `codepump/docs/padrao-desenvolvimento.md` — seção 23, origem deste padrão;
  `padroes-implementacao/padrao-api-config.md` — forma do endpoint.
* `admin-console-service` — onde a UI de configuração deste serviço vive.
* `roadmap.md` — entrada correspondente.
