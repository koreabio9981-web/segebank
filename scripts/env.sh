#!/bin/bash
# 공통 설정: 모든 배포 스크립트가 이 파일을 불러옴
APP_NAME="segebank"
APP_DIR="/home/ec2-user/segebank"
export PORT="${PORT:-3000}"
export NODE_ENV="production"

# CodeDeploy는 로그인 셸이 아니므로 node/pm2 경로를 직접 잡아 줌
export PATH="/usr/local/bin:/usr/bin:$PATH"
export NVM_DIR="/home/ec2-user/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
