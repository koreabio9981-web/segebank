#!/bin/bash
# 기존에 실행 중인 앱 중지 (처음 배포할 때는 앱이 없어도 정상으로 처리)
source "$(dirname "$0")/env.sh"
pm2 stop "$APP_NAME" 2>/dev/null || true
