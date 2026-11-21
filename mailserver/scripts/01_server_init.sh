#!/bin/bash
# 1회 실행: Ubuntu 24.04 EC2 초기 설정 (업데이트, 시간대, 스왑, 자동 보안패치, Docker)
# 사용법: sudo ./scripts/01_server_init.sh example.com
set -euo pipefail

DOMAIN="${1:-}"
[ "$(id -u)" -eq 0 ] || { echo "sudo 로 실행하세요."; exit 1; }
[ -n "$DOMAIN" ] || { echo "사용법: sudo $0 회사도메인.com"; exit 1; }
RUN_USER="${SUDO_USER:-ubuntu}"

echo "▶ 1/6 시스템 업데이트"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y curl git dnsutils unattended-upgrades awscli 2>/dev/null \
  || apt-get install -y curl git dnsutils unattended-upgrades

echo "▶ 2/6 시간대·서버 이름"
timedatectl set-timezone Asia/Seoul
hostnamectl set-hostname "mail.$DOMAIN"
grep -q "mail.$DOMAIN" /etc/hosts || echo "127.0.1.1 mail.$DOMAIN mail" >> /etc/hosts

echo "▶ 3/6 스왑 2GB"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile
  mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "▶ 4/6 보안 업데이트 자동 설치"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF

echo "▶ 5/6 Docker 설치"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
usermod -aG docker "$RUN_USER"
systemctl enable --now docker

echo "▶ 6/6 25번 포트를 쓰는 기존 메일 프로그램 정지(있으면)"
systemctl disable --now postfix 2>/dev/null || true

echo
echo "완료. 로그아웃 후 다시 접속하면 sudo 없이 docker 를 쓸 수 있습니다."
echo "다음: cp .env.example .env && chmod 600 .env  →  값 입력  →  ./scripts/02_start.sh"
