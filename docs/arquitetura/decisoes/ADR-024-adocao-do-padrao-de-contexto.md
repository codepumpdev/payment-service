# ADR-024 — Adoção do Padrão de Contexto: o Banco Vem da Identidade, Não da Configuração

- **Status:** Aceita
- **Data:** 2026-08-20
- **Origem:** `codepump/docs/padrao-desenvolvimento.md` §28; `codepump-lib` ADR-011 (`contextresolver`); `context-service` ADR-006/ADR-018/ADR-019

## Contexto

Pagamento é dado de um titular: `payments`, o histórico de status e os eventos de provedor existem por causa de um usuário ou de uma Organização. Pela arquitetura de Contextos (`context-service`, BD-01), esse dado vive no banco do Contexto do titular.

## Decisão

**O `payment-service` é um serviço contextual** (§28.2). `payments`, `payment_status_history`, `payment_provider_events` e `audit_logs` vivem no banco do Contexto, resolvido pelo `ContextResolver` a partir do claim `context` da identidade autenticada.

### O que muda

1. **Some da configuração** o banco de pagamentos. Entra o endereço do `context-service`.
2. **`ContextResolver` criado na inicialização**, encerrado no shutdown.
3. **Repositórios recebem o pool da operação**; nenhum guarda pool próprio nem conhece `Contexto → banco`.
4. **Sem Contexto, sem operação** (§28.8).

### O ponto sensível: webhook de provedor

Este serviço tem uma entrada que **não é uma requisição autenticada de usuário**: o webhook do provedor de pagamento, que chega com a identidade do provedor (ou só com uma assinatura), nunca com o `USER JWT` do titular.

A regra é: **o Contexto é resolvido a partir do pagamento, não do chamador.** O webhook traz o identificador da transação; o serviço precisa saber em qual Contexto aquele pagamento vive **antes** de poder abrir o banco onde ele está — e não pode varrer todos os bancos procurando, porque um serviço contextual não conhece banco nenhum.

Duas saídas, e a escolha fica registrada como ponto aberto porque depende do desenho do provedor:

1. **Carregar o Contexto no identificador que vai ao provedor** — o `payment-service` envia, na criação da transação, uma referência que ele mesmo compõe e que carrega o Contexto; o webhook devolve essa referência, e a resolução acontece direto.
2. **Manter um índice global `transação → Contexto`** no banco global do serviço, o que o tornaria misto.

A opção 1 é preferível: não cria dado global e não introduz uma segunda fonte de verdade sobre onde o pagamento está. A opção 2 é a saída se algum provedor não permitir referência própria.

Enquanto isso não estiver fechado, **o webhook não tem como operar** — e é melhor que essa lacuna esteja escrita do que resolvida por um banco padrão.

## Consequências

### Positivas

- Criar um Contexto novo não altera este serviço.
- O pagamento fica no mesmo banco do resto do dado do titular — pré-requisito da migração de sujeito (`context-service` BD-13).

### Negativas

- N pools em vez de um.
- **O webhook fica bloqueado até a decisão acima**; é a consequência mais concreta desta ADR neste serviço.
- **Conciliação entre Contextos deixa de ser uma consulta** e passa a ser iteração por Contexto (§28.7), com a lista vinda do `scheduler-service` ou do `context-service` — nunca de uma lista local de bancos.

## Critérios para reavaliar

A escolha entre as opções 1 e 2 do webhook deve ser fechada em ADR própria assim que o provedor de pagamento estiver definido. Se for a 2, este serviço passa a **misto** e o índice global precisa ser desenhado com cuidado: ele vira a única estrutura da plataforma que sabe onde um dado contextual está fora do `context-service`.

## Nota de integração

- `arquitetura/13-architecture.md`, `modelo-dados/19-data-model.md`, `contratos/17-api-contracts.md` (rota de webhook).
- `codepump/docs/padrao-desenvolvimento.md` §28 (em especial §28.7).
- **Implementação:** o serviço ainda não tem código; a adoção nasce junto com ele.

## Emenda — invalidação do cache (§28.10, 2026-08-20)

O serviço expõe `POST /internal/resetContext` (rota interna, `204 No Content`), que chama `resolver.Reset()` da `codepump-lib`: descarta todas as resoluções do processo, fecha os pools antigos e deixa a próxima utilização de cada Contexto resolver de novo — sem pré-carga e sem reinício.

É o que torna operável a mudança de infraestrutura de um Contexto já em uso. O procedimento é **alterar a infraestrutura → atualizar o `context-service` → resetar os serviços afetados → validar**, nessa ordem: resetar antes de atualizar o catálogo faz o serviço reresolver e cachear o endereço antigo de novo.

A invalidação é **local ao processo** — cobrir todas as instâncias é do procedimento operacional, não deste serviço.
