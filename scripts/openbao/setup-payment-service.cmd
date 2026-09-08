# ============================================================
# payment-service — OpenBao: policy, secrets e AppRole
# ============================================================
#
# Bloco único para colar num terminal já autenticado no OpenBao
# com um token de policy root (bao login).
#
# Nada é gravado em disco: a policy vai por stdin (bao policy
# write ... -), sem arquivo temporário no servidor.
#
# ------------------------------------------------------------
# ORDEM
# ------------------------------------------------------------
#
#   1. Cole este bloco. As senhas são geradas aqui.
#   2. No fim, ele imprime as duas linhas -v prontas para
#      colar em scripts/postgres/database.cmd.
#   3. Rode o database.cmd com essas senhas.
#
# BAO_ADDR usa o nome do serviço na rede do Compose.
# Ajuste se o cofre não for o do Compose local.
#
# Rodar duas vezes é seguro: engine, AppRole e secrets já
# existentes são preservados — e as senhas impressas no fim
# são lidas de volta do OpenBao, então refletem o que está
# realmente gravado.
#
# ============================================================

export BAO_ADDR="${BAO_ADDR:-http://openbao:8200}"

# Senhas geradas agora (exporte a variável antes de colar para
# usar um valor próprio)
OWNER_PASSWORD="${OWNER_PASSWORD:-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)}"
APP_PASSWORD="${APP_PASSWORD:-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)}"

# O client_secret M2M NÃO é gerado aqui, e a diferença importa: as senhas do
# banco são NOSSAS — nós as inventamos e o Postgres as aceita. O client_secret
# é do auth-service: ele o GERA no registro da Aplicação, guarda só o hash e o
# mostra UMA vez, na resposta.
#
# Gerar um valor aqui produzia uma entrada no cofre que PARECIA pronta e não
# autenticava em lugar nenhum — pior do que a entrada ausente, porque escondia
# o passo que faltava. O sintoma aparecia longe daqui: 401 na primeira chamada
# a outro serviço.
#
# O passo a passo está em scripts/auth/registrar-payment-service.md, e o
# essencial é impresso no fim deste script.

# Engine KV v2 e AppRole, se ainda não habilitados
bao secrets list | grep -q '^secret/'  || bao secrets enable -path=secret kv-v2
bao auth list    | grep -q '^approle/' || bao auth enable approle

# Policy — por stdin, sem arquivo temporário
bao policy write payment-service - << 'EOF'
path "secret/data/payment-service/database/command" {
  capabilities = ["read"]
}

path "secret/data/payment-service/database/query" {
  capabilities = ["read"]
}

path "secret/data/payment-service/m2m" {
  capabilities = ["read"]
}

path "secret/data/payment-service/providers/payment" {
  capabilities = ["read"]
}

path "secret/data/payment-service/providers/payment/*" {
  capabilities = ["read"]
}
EOF

# Secrets — um secret que já existe é preservado

# CQRS: command e query já provisionados. Com um único banco por
# serviço, os dois carregam o mesmo usuário e a mesma senha.
bao kv get -mount=secret payment-service/database/command >/dev/null 2>&1 || \
bao kv put -mount=secret payment-service/database/command \
    payment_owner_user='payment' \
    payment_owner_password="${OWNER_PASSWORD}" \
    payment_app_user='payment-app' \
    payment_app_password="${APP_PASSWORD}"

bao kv get -mount=secret payment-service/database/query >/dev/null 2>&1 || \
bao kv put -mount=secret payment-service/database/query \
    payment_owner_user='payment' \
    payment_owner_password="${OWNER_PASSWORD}" \
    payment_app_user='payment-app' \
    payment_app_password="${APP_PASSWORD}"

# Entrada M2M: os DOIS campos vêm do auth-service, e nenhum é o nome da
# Aplicação.
#
#   PAYMENT_SERVICE      é o ID DA APLICAÇÃO. Vai no `sub` do SERVICE JWT, e é
#                        por ele que o serviço de destino autoriza a chamada.
#
#   client_id            é o identificador da CREDENCIAL — opaco, gerado,
#                        algo como "aQ7x-KpR2mN4vT8sLb1wZg". Serve ao Basic Auth
#                        da emissão do token, e a mais nada.
#
# Confundi-los produz 401 na emissão: o auth-service procura a credencial
# pelo client_id, e o nome da Aplicação não é um.
#
# PENDENTE é marca deliberada, e não descuido: um campo AUSENTE faria o
# serviço subir e falhar com "campo não encontrado", e a mensagem não diria o
# que fazer. Assim, quem abrir o cofre vê o que falta.
bao kv get -mount=secret payment-service/m2m >/dev/null 2>&1 || \
bao kv put -mount=secret payment-service/m2m \
    client_id='PENDENTE-registrar-no-auth-service' \
    client_secret='PENDENTE-registrar-no-auth-service'

# Credenciais de Provider não são criadas aqui: cada fornecedor
# ganha o seu secret sob o path do canal, sob demanda — ex.:
#   bao kv put -mount=secret payment-service/providers/payment/nome api_key=...

# AppRole do serviço
bao write auth/approle/role/payment-service \
    token_policies=payment-service \
    token_type=service

# Role ID e Secret ID — anote o Secret ID, ele não é recuperável
bao read     auth/approle/role/payment-service/role-id
bao write -f auth/approle/role/payment-service/secret-id

# ------------------------------------------------------------
# Senhas do banco — lidas de volta do OpenBao
# Cole as duas linhas abaixo em scripts/postgres/database.cmd
# ------------------------------------------------------------
echo
echo "    -v owner_password='$(bao kv get -mount=secret -field=payment_owner_password payment-service/database/command)' \\"
echo "    -v app_password='$(bao kv get -mount=secret -field=payment_app_password payment-service/database/command)' \\"
echo

# ------------------------------------------------------------
# Credencial M2M — PENDENTE
# ------------------------------------------------------------
echo
echo "  ATENCAO - as credenciais M2M ainda NAO estao no cofre."
echo
echo "  Os dois saem do registro da Aplicacao, e o secret e mostrado UMA"
echo "  unica vez. Registre a Aplicacao la, com um token de administrador:"
echo
echo "    POST \$AUTH_URL/v1/admin/aplicacoes"
echo "         {\"id\":\"PAYMENT_SERVICE\",\"name\":\"PAYMENT_SERVICE\",\"external\":false}"
echo "    POST \$AUTH_URL/v1/admin/aplicacoes/PAYMENT_SERVICE/credenciais"
echo
echo "  Passo a passo: scripts/auth/registrar-payment-service.md"
echo
echo "  Copie clientId E clientSecret da resposta e grave os dois:"
echo
echo "    bao kv put -mount=secret payment-service/m2m \\"
echo "        client_id='<o clientId devolvido pelo auth-service>' \\"
echo "        client_secret='<o clientSecret devolvido>'"
echo
echo "  O clientId NAO e 'PAYMENT_SERVICE' - aquele e o ID da Aplicacao,"
echo "  e vai no sub do token. O clientId e opaco e gerado."
echo
echo "  Enquanto estiver PENDENTE, as chamadas M2M deste servico falham com 401."
echo
