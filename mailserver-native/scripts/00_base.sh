#!/bin/bash
# 1회: Ubuntu 24.04 기본 설정 (업데이트, 시간대, 서버 이름, 스왑, 자동 보안패치, AWS CLI)
# 사용법: sudo ./scripts/00_base.sh example.com
set -euo pipefail
DOMAIN="${1:-}"
[ "$(id -u)" -eq 0 ] || { echo "sudo 로 실행하세요."; exit 1; }
[ -n "$DOMAIN" ] || { echo "사용법: sudo $0 회사도메인"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

echo "▶ 업데이트"
apt-get update -y && apt-get upgrade -y
apt-get install -y curl dnsutils unattended-upgrades ca-certificates

echo "▶ 시간대·서버 이름"
timedatectl set-timezone Asia/Seoul
hostnamectl set-hostname "mail.$DOMAIN"
sed -i "/ mail\.$DOMAIN/d" /etc/hosts
echo "127.0.1.1 mail.$DOMAIN mail" >> /etc/hosts

echo "▶ 스왑 2GB"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "▶ 보안 업데이트 자동 설치"
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > /etc/apt/apt.conf.d/20auto-upgrades

echo "▶ AWS CLI (S3 백업용)"
command -v aws >/dev/null || snap install aws-cli --classic || echo "AWS CLI 설치 실패 (S3 백업을 쓰려면 수동 설치)"

echo "완료. 다음: cd /opt/mail && cp .env.example .env && chmod 600 .env → 값 입력 → sudo ./scripts/install.sh"
