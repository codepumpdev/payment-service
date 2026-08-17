# ADR-023 — CQRS: Separação Command/Query

- **Status:** Aceita
- **Data:** 2026-08-17

## Contexto

`padrao-desenvolvimento.md` (seção 15) tornou a separação Command/Query **obrigatória para todo serviço com banco de dados**, na mesma condição das seções 8.2, 12, 13 e 14. Antes disso a seção era de adoção opcional, e apenas `organization-service` a havia adotado (ADR-010 daquele serviço, primeiro precedente do monorepo). Esta ADR registra a adoção neste serviço — a decisão vem do padrão organizacional, não de uma necessidade de escala já observada aqui.

Este serviço persiste em um banco lógico exclusivo, `payment` (seção 8.2), com as entidades `payments`, `payment_status_history`, `payment_provider_events` (`modelo-dados/19-data-model.md`).

O processamento de webhook (ES-02) é Command, mesmo começando por uma verificação de idempotência que é leitura — a verificação roda dentro do Command, na conexão de Command (seção 15.6 do padrão).

## Decisão

1. **Command e Query separados desde o código**, na primeira versão — nunca como adição posterior. Layout de pacotes conforme a seção 15.3 do padrão (`internal/command/<entidade>/`, `internal/query/<entidade>/`).
2. **Duas conexões nomeadas e independentes:** `COMMAND_DATABASE_URL`/`QUERY_DATABASE_URL`, cada uma com o seu pool (`COMMAND_POOL`/`QUERY_POOL`, `MAX_CONNECTIONS` próprio) — apontando, **no MVP, para o mesmo banco `payment`**, com o mesmo usuário e a mesma senha, lidos de `secret/payment-service/database/command` e `secret/payment-service/database/query` (seção 8.1). O código **nunca assume** que as duas apontam para o mesmo lugar.
3. **Repositórios separados por entidade e por lado** — um de Command e um de Query, nunca os dois no mesmo tipo.
4. **Regra de negócio nunca abre conexão direto com o banco** — sempre via repositório.
5. **Command é a fonte oficial de alteração de estado**: recebe, valida, executa a regra, abre transação quando necessário, altera, comita. Transação sempre no lado Command. Leitura feita **dentro** de um Command (validação, verificação de existência) usa a conexão de Command, nunca a de Query (seção 15.6).
6. **Query é exclusivamente leitura** — nunca `INSERT`/`UPDATE`/`DELETE`, mesmo que a conexão tecnicamente tenha permissão de escrita nesta fase, por apontar para o mesmo banco. A separação é de responsabilidade de código, não depende de restrição de permissão para ser respeitada.
7. **`GET /ready` reporta `command-database` e `query-database` como dependências distintas** (seção 15.8, no formato `dependencies`/`responseTime` da seção 12.3).
8. **`GET /props` diferencia `database.command` de `database.query`** (seção 16.3).
9. **Migrações de schema (`golang-migrate`) sempre pela conexão de Command** — nunca pela de Query, mesmo antes de existir réplica; antecipa a topologia em que Query é somente-leitura e recusaria `ALTER TABLE`.
10. **Nenhuma réplica de leitura nesta fase.** Criar um segundo banco só para "fazer CQRS" violaria o próprio padrão (seção 15.7): a separação física fica reservada para necessidade real e comprovada de escala de leitura.
11. **Sem Event Sourcing** — a combinação é `CQRS + PostgreSQL`, sem replay de eventos para reconstruir estado.

## Consequências

### Positivas

- Separar os bancos no futuro passa a ser mudança de configuração e dos dois secrets — sem tocar em código de negócio.
- Torna explícito, desde o início, qual operação altera estado e qual só lê — o que também facilita revisar autorização e auditoria.
- Alinha este serviço ao restante da plataforma: mesmo layout de pacotes, mesmos nomes de conexão, mesmo contrato de `/ready` e `/props`.

### Negativas

- Mais estrutura desde o primeiro commit (dois repositórios por entidade, dois pools) do que a necessidade atual justifica isoladamente — o ganho é de padronização e de opção futura, não de desempenho hoje.
- Dois pools contra o mesmo PostgreSQL consomem mais conexões que um só; dimensionar `MAX_CONNECTIONS` de cada lado passa a ser um cuidado operacional.
- Enquanto as duas conexões apontarem para o mesmo banco com a mesma credencial, nada no banco **impede** uma escrita pelo lado Query — a garantia é de disciplina de código e revisão.

## Critérios para reavaliar

Separar fisicamente os bancos (réplica de leitura em `QUERY_DATABASE_URL`) quando houver evidência real: consultas consumindo recursos de forma desproporcional, contenção entre carga de leitura e de escrita, ou necessidade de isolar relatórios da operação. Até lá, manter o mesmo banco (seção 15.7).

## Nota de integração

* `arquitetura/15-infrastructure.md` — seção "Conexões Command e Query", com as duas URLs e o banco único do MVP.
* `codepump/codepump/docs/padrao-desenvolvimento.md` (seção 15) — origem normativa desta adoção; seção 8.1 para os paths `secret/payment-service/database/command` e `.../query`.
* `organization-service`, ADR-010 — primeiro precedente de CQRS no monorepo, referência de layout de pacotes e de repositórios.
