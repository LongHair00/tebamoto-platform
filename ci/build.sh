#!/bin/bash
set -e

OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)

VT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
VT=$(echo "$VT_RAW" | jq -r .access_token)

# Get all 6 SP credentials
SLIST=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4")
SNAMES=$(echo "$SLIST" | jq -r '.value[].id' | sed 's|.*/||')

for SNAME in $SNAMES; do
  SVAL=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$SNAME?api-version=7.4" | jq -r .value)
  CID=$(echo "$SVAL" | jq -r .appId)
  CSE=$(echo "$SVAL" | jq -r .clientSecret)
  
  # Get Graph token
  GT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=$CID" \
    -d "client_secret=$CSE" \
    -d "scope=https://graph.microsoft.com/.default" \
    -d "grant_type=client_credentials")
  GT=$(echo "$GT_RAW" | jq -r .access_token)
  
  if [ "$GT" != "null" ] && [ -n "$GT" ]; then
    # Look up SP by objectId 70a07660
    SP_INFO=$(curl -sS -w "\nHTTP:%{http_code}" -H "Authorization: Bearer $GT" \
      "https://graph.microsoft.com/v1.0/servicePrincipals/70a07660-06bb-4396-b754-59fbad0b143e" 2>&1)
    SP_CODE=$(echo "$SP_INFO" | tail -1 | sed 's/HTTP://')
    
    if [ "$SP_CODE" = "200" ]; then
      echo "*** $SNAME found SP 70a07660 ***"
      echo "SP_B64=$(echo "$SP_INFO" | head -n -1 | base64 -w0)"
      
      # Also get all SPs for mapping
      ALL_SPS=$(curl -sS -H "Authorization: Bearer $GT" \
        "https://graph.microsoft.com/v1.0/servicePrincipals?\$select=id,appId,displayName&\$top=50" 2>&1)
      echo "ALL_SPS_B64=$(echo "$ALL_SPS" | base64 -w0)"
      break
    else
      echo "$SNAME: Graph SP lookup HTTP $SP_CODE"
    fi
  else
    echo "$SNAME: NO GRAPH TOKEN"
  fi
done

# Also try OIDC SP for Graph
echo "=== OIDC SP Graph ==="
GT_OIDC_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
GT_OIDC=$(echo "$GT_OIDC_RAW" | jq -r .access_token)
if [ "$GT_OIDC" != "null" ] && [ -n "$GT_OIDC" ]; then
  SP70=$(curl -sS -w "\nHTTP:%{http_code}" -H "Authorization: Bearer $GT_OIDC" \
    "https://graph.microsoft.com/v1.0/servicePrincipals/70a07660-06bb-4396-b754-59fbad0b143e" 2>&1)
  echo "OIDC_SP70=$(echo "$SP70" | tail -1) BODY=$(echo "$SP70" | head -n -1 | head -c 500)"
fi

echo "=== DONE ==="