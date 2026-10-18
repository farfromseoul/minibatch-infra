#!/usr/bin/env bash
# SQLite 와 n8n 데이터를 날짜별로 백업한다. 백업은 내장 디스크(기본 ~/minibatch-backups)에 둔다:
# 데이터는 외장 NVMe 에 있으니 같은 디스크에 두면 디스크 고장 때 함께 잃는다 (2026-10-18).
# n8n 볼륨의 config 파일(암호화 키가 들어 있다)은 백업에 넣지 않는다. 키는 비밀 값 폴더와 비밀번호 관리자에 따로 둔다.
set -euo pipefail
: "${MINIBATCH_DATA_DIR:?MINIBATCH_DATA_DIR를 지정하세요}"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${MINIBATCH_BACKUP_DIR:-$HOME/minibatch-backups}"
DEST="$BACKUP_DIR/$STAMP"
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$DEST" "$MINIBATCH_DATA_DIR/backups"

# SQLite: DB 를 쓰는 job-api 컨테이너 안에서 sqlite3 백업 기능으로 일관된 복사본을 만든다.
# 호스트(맥)에서 sqlite3 로 읽으면 컨테이너와 공유 메모리(-shm)를 함께 보지 못해 최근 내용이 빠질 수 있다
# (2026-10-18 실제: 호스트에서 바꾼 값을 실행 중인 컨테이너가 못 읽음)
(cd "$INFRA" && docker compose exec -T job-api python -c "
import sqlite3
src = sqlite3.connect('/data/db/minibatch.sqlite'); dst = sqlite3.connect('/data/backups/minibatch.sqlite.tmp')
src.backup(dst); dst.close(); src.close()")
mv "$MINIBATCH_DATA_DIR/backups/minibatch.sqlite.tmp" "$DEST/minibatch.sqlite"
sqlite3 "$DEST/minibatch.sqlite" "pragma integrity_check" | grep -qx ok || { echo "실패: 백업 DB 무결성 검사" >&2; exit 1; }

# n8n 데이터 볼륨 (워크플로, 암호화된 자격 증명). config(키)는 뺀다
docker run --rm -v minibatch_n8n_data:/src:ro -v "$DEST":/dest alpine:3.24.2 \
  tar czf /dest/n8n_data.tgz --exclude=./config -C /src .

# 키가 빠졌는지 확인한다. 들어 있으면 백업을 지우고 실패한다
if docker run --rm -v "$DEST":/dest:ro alpine:3.24.2 tar tzf /dest/n8n_data.tgz | grep -qx './config'; then
  rm -f "$DEST/n8n_data.tgz"
  echo "실패: n8n_data.tgz 에 config(암호화 키)가 들어 있어 지웠습니다" >&2
  exit 1
fi

# 14일 지난 백업 삭제
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
echo "백업: $DEST"
