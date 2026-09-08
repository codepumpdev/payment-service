# Registro do `payment-service` como Aplicação no `auth-service`

Passo **operacional**, feito uma vez por ambiente. Emite a Credencial de Aplicação
(BD-12) com que este serviço obtém o SERVICE JWT das chamadas de saída (§9.3).

> **Este serviço ainda NÃO tem código.** O registro é feito quando ele for
> implantado — não agora. Registrar antes cria uma credencial que fica parada no
> cofre, e que provavelmente terá de ser reemitida quando a implantação
> acontecer de verdade. Este documento existe para o dia em que isso acontecer.

## Por que o `client_secret` não sai do cofre

Ele é **gerado pelo `auth-service`** — `RandomToken(32)` — e mostrado **uma única
vez**, na resposta do registro. O `auth-service` guarda apenas o hash, e não há
rota que o devolva depois.

O script `scripts/openbao/setup-payment-service.cmd` **gerava** um valor local até
2026-09-07, e essa entrada nunca autenticou em lugar nenhum. Hoje ele grava
`PENDENTE-registrar-no-auth-service`, que é o que este documento resolve.

> Se o serviço já foi implantado antes dessa correção, o cofre tem o valor
> inútil. O script **preserva entradas existentes**, então rodá-lo de novo não
> corrige — é preciso o `bao kv put` do passo 4.

## 1. Obter um token de administrador

```bash
curl -sS -X POST "$AUTH_URL/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"login":"admin","password":"admin","app":"AUTH_SERVICE"}'
```

Na instalação nova, a credencial é a do bootstrap do `auth-service`. Trocá-la é
parte da implantação, não deste passo.

## 2. Criar a Aplicação

```bash
curl -sS -X POST "$AUTH_URL/v1/admin/aplicacoes" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"id":"PAYMENT_SERVICE","name":"Payment Service","external":false}'
```

O `id` é identificador de negócio, legível e **estável entre ambientes** — e é
ele que vira o `sub` do SERVICE JWT. Precisa ser exatamente `PAYMENT_SERVICE`:
é o valor que o cofre já grava em `payment-service/m2m`, e é por ele que outro serviço
pode vir a autorizar (ou recusar) uma chamada.

## 3. Emitir a Credencial de Aplicação

```bash
curl -sS -X POST "$AUTH_URL/v1/admin/aplicacoes/PAYMENT_SERVICE/credenciais" \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

A resposta traz `clientId` e `clientSecret`. **Copie os dois agora** — o secret
não aparece de novo.

> **O `clientId` NÃO é `PAYMENT_SERVICE`.** São duas coisas com nomes
> parecidos, e confundi-las produz `401` na emissão do token:
> 
> | | O que é | Onde aparece |
> |---|---|---|
> | `PAYMENT_SERVICE` | id da **Aplicação** | no `sub` do SERVICE JWT — é por ele que o destino autoriza |
> | `clientId` | id da **Credencial**, opaco e gerado | só no Basic Auth da emissão |
> 
> O `auth-service` procura a credencial pelo `clientId`, e o nome da Aplicação
> não é um.

Perder o secret não é fatal: emite-se outra credencial. Mas a antiga continua
valendo até ser removida, e credencial órfã é o tipo de coisa que ninguém
encontra depois.

## 4. Guardar no cofre

```bash
bao kv put -mount=secret payment-service/m2m \
    client_id='<o clientId devolvido no passo 3>' \
    client_secret='<o clientSecret devolvido no passo 3>'
```

## 5. Configurar o serviço

```
AUTH_SERVICE_URL=http://auth-service:8080
AUTH_CLIENT_ID=<o clientId do cofre — opaco, NÃO é PAYMENT_SERVICE>
AUTH_CLIENT_SECRET=<do cofre>
```

## O que não funciona sem isto

- **Aviso de pagamento ao `billing-service`** (`POST /v1/billings/{id}/payment-events`), que é o que dispara a atualização da validade do acesso (ADR-025, decisão 2).
- **Consulta ao `person-service`** para os dados do recebedor.

## Verificar

```bash
curl -sS -X POST "$AUTH_URL/oauth2/v1/token/service" \
  -u "$CLIENT_ID:$CLIENT_SECRET"   # o clientId opaco, não o nome da Aplicação
```

Resposta com `accessToken` significa credencial válida. `401` significa que o
secret do cofre não é o que o `auth-service` conhece — quase sempre porque o
passo 4 não foi feito, ou foi feito com o valor gerado pelo script antigo.

## O que NÃO é preciso

**Nenhuma Concessão de Perfil (BD-24) por causa deste registro.** A Concessão é
exigida pelo serviço **chamado**, para a operação que ele expõe — e é decidida lá,
caso a caso. Registrar a Aplicação só emite a identidade; o que ela pode fazer em
cada destino é outra conversa, e conceder Perfis "por precaução" aqui daria
alcance que ninguém pediu.

> **Mas ao menos UMA concessão é preciso, seja qual for.** Uma Aplicação com
> zero concessões recebe `403 ACESSO_NEGADO` já na emissão do token:
> `IssueServiceToken` recusa antes de montar os `profiles`. O sintoma engana —
> a credencial está certa, e a mensagem fala de perfil, não de credencial. Na
> prática isso não aparece, porque a primeira Concessão de verdade vem junto do
> primeiro destino que este serviço precisa chamar.
