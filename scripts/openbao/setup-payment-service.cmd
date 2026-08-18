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
M2M_CLIENT_SECRET="${M2M_CLIENT_SECRET:-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 48)}"

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

bao kv get -mount=secret payment-service/m2m >/dev/null 2>&1 || \
bao kv put -mount=secret payment-service/m2m \
    client_id='PAYMENT_SERVICE' \
    client_secret="${M2M_CLIENT_SECRET}"

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
