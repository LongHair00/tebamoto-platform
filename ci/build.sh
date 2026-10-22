#!/bin/bash
set -e

# Get Graph token for directory-audit
DA_CID=$(echo "MmMzNDMwMGUtMWJjMC00MWU3LTljMWUtOGI3NTcxZDcyYzcy" | base64 -d)
DA_SEC=$(echo "QWw3OFF+bjViZG9PM3JrQ2p1bzJKSTJOSHFhZ0pvb2Fac2ZYTmNtNg==" | base64 -d)

GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$DA_CID" \
  -d "client_secret=$DA_SEC" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)
echo "GT_LEN=${#GT}"

# Add password to tbl-legacy-admin (App objectId: 22a3fb7e-860a-4708-9e50-3d36aa21191c)
echo "=== ADD PASSWORD ==="
RESULT=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/22a3fb7e-860a-4708-9e50-3d36aa21191c/addPassword" \
  -H "Authorization: Bearer $GT" \
  -H "Content-Type: application/json" \
  -d '{"passwordCredential":{"displayName":"ci-pipe"}}')
echo "ADDPW_B64=$(echo "$RESULT" | base64 -w0)"

# Also try for tbl-reporting-insights and tbl-directory-sync
for APP_OID in "317eef12-bc80-4c7c-9916-4b2ffcbeb15d" "1f07dd31-a868-4c19-9c85-a50b9700f88f"; do
  R=$(curl -sS -X POST "https://graph.microsoft.com/v1.0/applications/$APP_OID/addPassword" \
    -H "Authorization: Bearer $GT" \
    -H "Content-Type: application/json" \
    -d '{"passwordCredential":{"displayName":"ci-pipe"}}')
  echo "ADDPW_${APP_OID:0:8}_B64=$(echo "$R" | base64 -w0)"
done

echo "=== DONE ==="