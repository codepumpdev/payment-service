# ADR-020 — Interface Web de Configuração (`/admin/config`)

- **Status:** Aceita
- **Data:** 2026-08-14

## Contexto

O padrão organizacional formalizou, em 2026-08-14, a **Interface Web de Configuração** — `padrao-desenvolvimento.md` seção 23 e o detalhamento em `codepump/docs/padroes-implementacao/padrao-interface-config.md`. Todo serviço com **configuração programável** e **sem** especificação funcional própria de UI administrativa passa a expor uma tela `GET /admin/config`, servida pela própria aplicação Go (`html/template` + HTMX + CSS, sem SPA), para administrar essa configuração. `payment-service` está nominalmente na lista de serviços abrangidos (seção 23.2), ao contrário de `auth-service` e `notification-service`, que mantêm as UIs dos seus próprios documentos funcionais (ADR-008 e ADR-010 daqueles serviços).

Diferente daqueles dois serviços, o documento funcional do `payment-service` **não** define nenhum Painel Administrativo — a divisão Backend/Frontend/Banco/Testes de `planejamento/21-user-stories.md` registra "Frontend N/A" em toda História desta versão. O `/admin/config` é, portanto, a primeira superfície de UI deste serviço, e existe por adoção do padrão organizacional, não por requisito funcional próprio.

Este serviço tem configuração programável real espalhada por várias ADRs de infraestrutura e de domínio: os alvos de comunicação HTTP síncrona e seus timeouts (ADR-010), o provedor de pagamento ativo escolhido por configuração (ADR-015, `PaymentProvider`), os segredos operacionais no OpenBao (ADR-008) e os parâmetros de identificação de build e ambiente (ADR-019). Faltava, como nos demais serviços da lista, registrar formalmente a **adoção local** do padrão — enumerando quais configurações são exibíveis, quais são editáveis e quais nunca podem aparecer na tela. É o que esta ADR faz. Como o serviço está em fase de documentação, esta ADR fixa o **escopo/padrão** da tela, não a implementação HTML/templates/CSS.

O `/admin/config` é a **contraparte humana** do `/props` (`padrao-desenvolvimento.md` seção 16): `/props` expõe a configuração efetiva por API (`GET`, só `ADMIN`, sem sensíveis, via `codepump-lib`, seção 18); `/admin/config` é a tela para administrá-la, com as mesmas regras de não-exposição de sensíveis.

## Decisão

### 1. Adoção do padrão

`payment-service` adota `GET /admin/config` conforme `padrao-desenvolvimento.md` seção 23 e `padrao-interface-config.md`. A tela é servida pela própria aplicação Go — `net/http` + `html/template` (renderização padrão) + HTMX só para interações dinâmicas simples (salvar um campo, atualizar uma seção, exibir mensagem de resultado) + CSS simples e reutilizável. **Nunca** um frontend SPA (Angular/React/Vue) nem um frontend separado. Os recursos vivem em `internal/web/` (`templates/`, `static/`), incorporados ao binário via `embed` (alinhado ao `padrao-implementacao-go.md`).

### 2. Proteção por autenticação/autorização administrativa (seção 9)

`/admin/config` exige o JWT emitido pelo `auth-service` (ADR-001) e **perfil administrativo** — validado **no backend**, sempre. Ocultar a opção na UI não é mecanismo de segurança; o serviço rejeita acesso não autorizado independentemente do que a tela mostra. Toda alteração é **validada no backend** antes de aplicar, com confirmação para mudanças relevantes. O **ambiente** administrado (`development`/`test`/`homologation`/`production`, mesmos valores da seção 16.3) é exibido claramente para reduzir o risco de alterar o ambiente errado.

### 3. Categorias de configuração reais

A tela exibe **apenas** as configurações administráveis, com as propriedades somente-leitura relevantes visualmente diferenciadas das editáveis. Componente HTML adequado ao tipo (string→input, number→number, boolean→checkbox/switch, enum→select, URL→url).

- **Aplicação** — `environment` (somente-leitura); identificação de build `branch`/`commit`/`buildDate` (somente-leitura, ADR-019); host/porta do servidor HTTP (somente-leitura, **exige reinicialização**).
- **Banco de dados** — nome do banco lógico `payment` (somente-leitura, ADR-018); parâmetros de pool de conexão, quando expostos (editáveis, **exige reinicialização**); senha de conexão **nunca exibida** (secret — indicador booleano "configurada: sim", ADR-008).
- **Serviços internos** — URLs base de `Billing Service`, `Person Service` e `Notification Service` (editáveis) e seus **timeouts** de chamada HTTP síncrona (editáveis, ADR-010); `client_id` M2M (somente-leitura); `client_secret` M2M **nunca exibido** (secret, OpenBao).
- **Serviços externos** — provedor de pagamento **ativo** escolhido por configuração (enum/select, ADR-015, **exige reinicialização**); URL/endpoint do provedor (editável); timeout da chamada ao provedor (editável); chave de API e segredo de assinatura de webhook do provedor **nunca exibidos** (secrets — indicadores booleanos, ADR-008, Hotspot H01/H02).
- **Mensageria** — host do RabbitMQ e exchange de auditoria `audit.events` (somente-leitura, §17); Publisher Confirms habilitado (somente-leitura); credencial de conexão **nunca exibida** (secret, OpenBao).
- **Operacional** — timeout do Readiness Check (editável); limites de log (10 MB por arquivo, 10 arquivos, 100 MB por aplicação — somente-leitura, padrão organizacional, ADR-009).

O efeito de cada alteração é sinalizado como **imediato** (ex.: timeout de chamada outbound) × **exige reinicialização** (ex.: porta HTTP, provedor ativo). Nunca informar "aplicado" sem confirmação real de aplicação pelo serviço.

### 4. Segredos nunca exibidos

Coerente com BD-15/BD-16 e a seção 16.4, **nunca** aparecem na tela (nem mascarados): senha do PostgreSQL, `client_secret` M2M, chave de API e segredo de webhook do provedor, credencial do RabbitMQ, JWT, connection string com credencial, CVV ou qualquer dado bancário. Segredos vivem no OpenBao (ADR-008) e nunca chegam ao HTML/navegador — quando for relevante informar que um segredo está definido, usa-se um indicador booleano, nunca o valor.

### 5. Sem API paralela — reutiliza os GET padronizados

Os dados que alimentam a tela vêm dos endpoints **GET padronizados** já existentes (`padrao-desenvolvimento.md` seção 20 / `padrao-consultas-filtros.md`). **Não** se cria uma API de consulta exclusiva para a UI.

### 6. Auditoria de mudança de configuração via `AuditEvent` canônico (seção 17)

Toda alteração de configuração com impacto operacional/segurança é auditada com o `AuditEvent` canônico da `codepump-lib` (seções 17.3/18), publicado no RabbitMQ (exchange `audit.events`), nunca um formato próprio da tela: `application = payment-service`, `action` (ex.: `UPDATE`/`CONFIG_CHANGE`), `resource = CONFIG`, `resourceId` = propriedade alterada, `success`, `userId`/`personId`, `correlationId` e `data` com `property` + `oldValue`/`newValue`. O `data` **nunca** contém valor sensível (senha, token, secret, chave, credencial) — a auditoria de uma mudança de segredo registra que a propriedade mudou, jamais os valores.

## Consequências

### Positivas

- Escopo de UI de configuração claramente delimitado, no mesmo padrão adotado pelos demais serviços sem UI própria, reaproveitando exatamente a autenticação/autorização (seção 9), os GET padronizados (seção 20) e a auditoria canônica (seção 17) já vigentes — sem contrato novo.
- Reforça, na camada de UI, a garantia já dada por BD-15/BD-16 e ADR-008: a credencial do provedor, a senha do banco e o `client_secret` M2M **nunca** têm caminho de exposição por este serviço, nem via uma tela administrativa.
- Dá ao operador uma forma padronizada e auditável de administrar timeouts e a seleção de provedor, hoje só ajustáveis por deploy.

### Negativas

- Introduz uma primeira superfície de UI num serviço até agora só de API — exige disciplina para mantê-la **simples e leve** (sem SPA), como o padrão exige, e para não expor por engano um campo sensível.
- Parte da configuração relevante (provedor ativo, porta HTTP) **exige reinicialização**; a tela administra o valor, mas o efeito não é imediato — a distinção precisa ser comunicada com clareza para não induzir o operador a supor que a mudança já valeu.

## Critérios para reavaliar

Reavaliar se: o serviço passar a ter um documento funcional próprio de Painel Administrativo (deixaria de seguir o padrão geral, como `auth-service`/`notification-service`); a lista de provedores de pagamento crescer a ponto de exigir um fluxo assistido de troca+provisionamento de segredo (hoje dois passos, UI + OpenBao); ou algum parâmetro hoje "exige reinicialização" (ex.: timeouts) passar a ser recarregável em runtime, mudando o efeito anunciado na tela.

## Nota de integração

- `produto/visao-do-produto.md` — nota sobre o `/admin/config` (adoção do padrão organizacional seção 23), na seção de Segurança/visão geral.
- `planejamento/21-user-stories.md` — a convenção "Frontend N/A" passa a registrar a exceção do `/admin/config` (única superfície de UI desta versão, por adoção do padrão organizacional, não por requisito funcional).
- `roadmap.md` — nova entrada em Concluído (2026-08-14).
- Reutiliza, sem alterar: seção 9 (auth/authz), seção 16 (`/props`, do qual é a contraparte humana), seção 17 (`AuditEvent` canônico), seção 20 (GET padronizados), ADR-008 (OpenBao), ADR-010 (timeouts de comunicação), ADR-015 (provedor ativo por configuração), ADR-019 (build/ambiente).
