# ADR-010 — Comunicação HTTP Síncrona com Serviços Externos e Provedor (Sem RabbitMQ)

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

`padrao-desenvolvimento.md` (seção 2) fixa RabbitMQ como ponto de partida padrão sempre que um novo serviço precisar desacoplar produtor e consumidor de forma assíncrona. Diferente de `billing-service`, o documento funcional deste serviço não contém uma instrução textual explícita pedindo comunicação HTTP direta — mas toda a descrição de fluxo (seções 13, 14, 18, 26 da especificação) descreve chamadas request/response diretas entre `Payment Service` e `Billing Service`/`Person Service`/`Notification Service`/`Payment Provider`, sem nenhuma menção a fila, e a seção 39 pede explicitamente "priorize uma implementação simples, pequena e adequada ao porte da empresa" — mesma orientação geral que já levou `billing-service` a este mesmo desvio.

## Decisão

`Payment Service` se comunica com `Billing Service` (consulta + informe), `Person Service` (consulta), `Notification Service` (publicação de evento) e `Payment Provider` (envio da operação + webhook) via chamada HTTP síncrona nesta versão — **nenhum RabbitMQ, nenhuma fila, nenhum broker**. Todos os seis eventos de domínio do catálogo inicial (`PAYMENT_CREATED`, `PAYMENT_PROCESSING`, `PAYMENT_APPROVED`, `PAYMENT_REJECTED`, `PAYMENT_CANCELLED`, `PAYMENT_REFUNDED`) são modelados como eventos de domínio (para fins de nomenclatura/documentação, `18-event-contracts.md`), mas transportados via HTTP direto, não via mensageria — mesma decisão já adotada por `billing-service` (ADR-010 daquele serviço), agora estendida a um terceiro serviço financeiro da organização.

## Consequências

### Positivas

- Infraestrutura mais simples, adequada ao porte da empresa — sem operar um cluster RabbitMQ adicional só para este serviço.
- Consistente com a orientação geral de simplicidade repetida ao longo de toda a especificação (seção 39).

### Negativas

- Acoplamento temporal entre os serviços — se `Billing Service`, `Person Service`, `Notification Service` ou o `Payment Provider` estiverem indisponíveis no momento da chamada, a operação falha ou fica pendente de retry manual/aplicação, sem o amortecimento natural de uma fila (RNF-09).
- Nenhuma garantia de entrega além do que uma chamada HTTP síncrona oferece — se a chamada outbound falhar depois que a transação de banco já foi commitada, o informe ao `Billing Service`/`Notification Service` pode se perder sem um mecanismo de reprocessamento automático nesta versão.

## Critérios para reavaliar

Quando a necessidade de desacoplamento/processamento assíncrono for real — volume que justifique buffering, necessidade de retry com backoff automatizado, ou múltiplos consumidores independentes do mesmo evento (mesmos critérios já registrados por `notification-service`, ADR-008 daquele serviço, e por `billing-service`, ADR-010 daquele serviço).

## Nota de integração

* `dominio/03-business-decisions.md` (BD-14).
* `arquitetura/13-architecture.md`.
* `arquitetura/15-infrastructure.md`.
* `contratos/18-event-contracts.md`.
* `requisitos/11-non-functional-requirements.md` (RNF-09 — tensão registrada).
* `codepump/codepump/docs/padrao-desenvolvimento.md`, seção 2.
