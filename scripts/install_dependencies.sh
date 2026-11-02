#!/bin/bash
# 운영에 필요한 패키지만 설치
set -e
source "$(dirname "$0")/env.sh"
cd "$APP_DIR"
npm ci --omit=dev
