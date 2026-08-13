# ADR-015 — Abstração `PaymentProvider`

- **Status:** Aceita
- **Data:** 2026-08-13

## Contexto

O documento funcional (seção 17) é explícito: "não acople as regras de negócio diretamente ao provedor. Crie uma abstração." Cita "Provider A"/"Provider B"/"Provider C" como exemplos ilustrativos de múltiplas implementações possíveis, escolhidas por configuração — mas nesta versão só um provedor real será integrado (nome ainda não definido, Hotspot H01).

## Decisão

`Payment Service` define uma interface `PaymentProvider` na camada `internal/infrastructure/provider/` (ADR-003), com operações conceituais `EnviarOperacao`, `InterpretarWebhook` e `ValidarAutenticidade` (`07-domain-services.md`, Serviço de Integração com Provedor). Nenhuma camada de domínio (`internal/domain/`) importa ou referencia o SDK/API específico de um provedor. O provedor concreto ativo é escolhido por configuração (variável de ambiente/OpenBao), nunca por lógica de negócio nesta versão.

## Consequências

### Positivas

- Trocar de provedor, ou adicionar um segundo, não exige alterar nenhuma regra de domínio — só uma nova implementação da interface.
- Testes de domínio podem usar uma implementação fake de `PaymentProvider`, sem depender de rede/provedor real.

### Negativas

- Overhead de uma camada de abstração adicional para um único provedor implementado nesta versão — aceito, é o custo de manter o desacoplamento pedido explicitamente pelo documento funcional, mesmo antes de haver um segundo provedor real.

## Critérios para reavaliar

Quando um segundo provedor for implementado — validar que a interface, desenhada só com um provedor real em produção, realmente generaliza (risco conhecido de abstração prematura, mitigado por manter a interface mínima).

## Nota de integração

* `dominio/03-business-decisions.md` (BD-13).
* `dominio/07-domain-services.md` (Serviço de Integração com Provedor).
* `arquitetura/13-architecture.md`.
* `dominio/01-event-storming-big-picture.md` (Hotspot H01, H02).
