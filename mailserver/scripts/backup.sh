#!/bin/bash
# 매일 백업: 메일함·설정·웹메일 DB·메일러 DB → backups/ (선택: S3 업로드)
# root 권한으로 실행합니다.
# 등록: sudo crontab -e  →  30 3 * * * /opt/mail/scripts/backup.sh >> /opt/mail/backups/backup.log 2>&1
. "$(dirname "$0")/common.sh"
[ "$(id -u)" -eq 0 ] || die "sudo 로 실행하세요."
load_env
cd "$MAIL_DIR"

STAMP="$(date +%Y%m%d-%H%M)"
OUT="$MAIL_DIR/backups"
mkdir -p "$OUT"

echo "[$STAMP] 메일러 DB 덤프"
docker compose exec -T listmonk-db pg_dump -U listmonk listmonk | gzip > "$OUT/listmonk-$STAMP.sql.gz"

echo "[$STAMP] 메일함·설정 압축"
tar -czf "$OUT/mail-$STAMP.tar.gz" -C "$MAIL_DIR" data/dms data/roundcube .env
chmod 600 "$OUT"/*-"$STAMP".*

if [ -n "${BACKUP_S3_BUCKET:-}" ]; then
  echo "[$STAMP] S3 업로드 → s3://$BACKUP_S3_BUCKET/"
  aws s3 cp "$OUT/listmonk-$STAMP.sql.gz" "s3://$BACKUP_S3_BUCKET/$STAMP/" --only-show-errors
  aws s3 cp "$OUT/mail-$STAMP.tar.gz"     "s3://$BACKUP_S3_BUCKET/$STAMP/" --only-show-errors
fi

find "$OUT" -name '*.gz' -mtime +"${BACKUP_KEEP_DAYS:-7}" -delete
echo "[$STAMP] 완료: $(du -sh "$OUT" | cut -f1)"
