#!/bin/bash
# PM2로 앱 실행 (package.json의 "start" 스크립트 사용)
set -e
source "$(dirname "$0")/env.sh"
cd "$APP_DIR"
pm2 delete "$APP_NAME" 2>/dev/null || true
pm2 start npm --name "$APP_NAME" -- start
pm2 save
