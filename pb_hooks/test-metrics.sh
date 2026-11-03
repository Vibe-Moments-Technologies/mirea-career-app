#!/bin/bash
# Полный тест хука счётчиков (чистый bash — без экранирования PowerShell)
set -u
PB=http://127.0.0.1:8090

echo "--- view v1 ---"
curl -s -X POST $PB/api/metrics/view/xqf7d3xgu9yzx2b -H 'X-Visitor-Id: v1'; echo
echo "--- view v1 again (dedupe) ---"
curl -s -X POST $PB/api/metrics/view/xqf7d3xgu9yzx2b -H 'X-Visitor-Id: v1'; echo
echo "--- view v2 ---"
curl -s -X POST $PB/api/metrics/view/xqf7d3xgu9yzx2b -H 'X-Visitor-Id: v2'; echo
echo "--- favorite +1 ---"
curl -s -X POST $PB/api/metrics/favorite -H 'Content-Type: application/json' -d '{"post_id":"xqf7d3xgu9yzx2b","delta":1}'; echo
echo "--- favorite -5 (clamp) ---"
curl -s -X POST $PB/api/metrics/favorite -H 'Content-Type: application/json' -d '{"post_id":"xqf7d3xgu9yzx2b","delta":-5}'; echo
echo "--- favorite bad delta ---"
curl -s -X POST $PB/api/metrics/favorite -H 'Content-Type: application/json' -d '{"post_id":"xqf7d3xgu9yzx2b","delta":5}'; echo
echo "--- view nonexistent ---"
curl -s -X POST $PB/api/metrics/view/zzzz; echo
echo "--- counters after ---"
curl -s "$PB/api/collections/posts/records/xqf7d3xgu9yzx2b?fields=views_count,favorites_count"; echo
