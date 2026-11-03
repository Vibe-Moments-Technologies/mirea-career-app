#!/bin/bash
TOK=$(curl -s -X POST http://127.0.0.1:8090/api/collections/_superusers/auth-with-password \
  -H 'Content-Type: application/json' \
  -d '{"identity":"admin@l1ratch.ru","password":"MireaCareer2026!"}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["token"])')
curl -s "http://127.0.0.1:8090/api/logs?sort=-created&perPage=50" \
  -H "Authorization: $TOK" \
  | python3 -c '
import sys, json
data = json.load(sys.stdin)
for it in data.get("items", []):
    d = it.get("data") or {}
    if "metrics" in (d.get("url") or ""):
        print(json.dumps(it, ensure_ascii=False)[:1200])
        print("---")
'
