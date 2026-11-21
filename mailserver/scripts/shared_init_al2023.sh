#!/bin/bash
# [공용 서버 모드] Amazon Linux 2023 준비: Docker, Compose, 스왑, Nginx, certbot
# 소개뱅크 앱(PM2, 3000 포트)과 서버 이름은 건드리지 않습니다.
# 사용법: sudo ./scripts/shared_init_al2023.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "sudo 로 실행하세요."; exit 1; }

echo "▶ 1/5 Docker"
dnf install -y bind-utils tar >/dev/null   # dig(DNS 점검), tar(백업)
if ! command -v docker >/dev/null; then
  dnf install -y docker
fi
systemctl enable --now docker
usermod -aG docker ec2-user

echo "▶ 2/5 Docker Compose 플러그인"
if ! docker compose version >/dev/null 2>&1; then
  mkdir -p /usr/local/lib/docker/cli-plugins
  arch=$(uname -m)   # x86_64 또는 aarch64
  curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$arch" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi
docker compose version

echo "▶ 3/5 스왑 2GB (없을 때만)"
if [ "$(awk '/SwapTotal/ {print $2}' /proc/meminfo)" -eq 0 ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "▶ 4/5 Nginx (이미 있으면 그대로 사용)"
if ! command -v nginx >/dev/null; then
  dnf install -y nginx
  systemctl enable --now nginx
fi
mkdir -p /var/www/certbot

echo "▶ 5/5 certbot"
if ! command -v certbot >/dev/null; then
  dnf install -y certbot || {
    dnf install -y python3-pip
    python3 -m venv /opt/certbot && /opt/certbot/bin/pip install -q certbot
    ln -sf /opt/certbot/bin/certbot /usr/bin/certbot
  }
fi
# 자동 갱신 (systemd 타이머가 있으면 사용, 없으면 cron)
systemctl enable --now certbot-renew.timer 2>/dev/null \
  || echo "17 3,15 * * * root certbot renew -q" > /etc/cron.d/certbot-renew
# 갱신 후 Nginx·메일서버에 반영
mkdir -p /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/mail-reload.sh <<'HOOK'
#!/bin/bash
systemctl reload nginx
docker restart mailserver >/dev/null 2>&1 || true
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/mail-reload.sh

echo
echo "완료. 로그아웃 후 다시 접속하면 sudo 없이 docker 사용 가능."
echo "다음: cd /opt/mail && cp .env.example .env && chmod 600 .env → 값 입력 → ./scripts/shared_start.sh"
