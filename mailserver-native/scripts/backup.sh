#!/bin/bash
# 매일 백업: 메일함·설정·웹메일 DB·메일러 DB → backups/ (선택: S3 업로드)
# 등록: sudo crontab -e  →  30 3 * * * /opt/mail/scripts/backup.sh >> /opt/mail/backups/backup.log 2>&1
. "$(dirname "$0")/common.sh"
need_root
load_env
STAMP="$(date +%Y%m%d-%H%M)"; OUT="$MAIL_DIR/backups"; mkdir -p "$OUT"; chmod 700 "$OUT"
export PATH="$PATH:/snap/bin"

echo "[$STAMP] 메일러 DB"
sudo -u postgres pg_dump listmonk | gzip > "$OUT/listmonk-$STAMP.sql.gz"

echo "[$STAMP] 메일함·설정"
tar -czf "$OUT/mail-$STAMP.tar.gz" --ignore-failed-read \
  /var/vmail /etc/postfix /etc/dovecot /etc/rspamd/local.d /etc/roundcube \
  /var/lib/dbconfig-common/sqlite3/roundcube /opt/listmonk/config.toml /etc/letsencrypt \
  /etc/nginx/sites-available/mail.conf "$ENV_FILE" 2>/dev/null
chmod 600 "$OUT"/*-"$STAMP".*

if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
  echo "[$STAMP] S3 → s3://$BACKUP_S3_BUCKET/$STAMP/"
  aws s3 cp "$OUT/listmonk-$STAMP.sql.gz" "s3://$BACKUP_S3_BUCKET/$STAMP/" --only-show-errors
  aws s3 cp "$OUT/mail-$STAMP.tar.gz"     "s3://$BACKUP_S3_BUCKET/$STAMP/" --only-show-errors
fi
find "$OUT" -name '*.gz' -mtime +"${BACKUP_KEEP_DAYS:-7}" -delete
echo "[$STAMP] 완료 $(du -sh "$OUT" | cut -f1)"
