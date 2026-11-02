#!/bin/bash
# 앱이 실제로 응답하는지 확인 (최대 60초 대기)
source "$(dirname "$0")/env.sh"
for i in $(seq 1 30); do
  if curl -fs "http://localhost:${PORT}/" > /dev/null; then
    echo "OK: 앱이 ${PORT}번 포트에서 응답합니다"
    exit 0
  fi
  sleep 2
done
echo "FAIL: 앱이 응답하지 않습니다. 'pm2 logs ${APP_NAME}'로 확인하세요"
exit 1
