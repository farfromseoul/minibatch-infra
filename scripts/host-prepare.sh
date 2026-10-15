#!/usr/bin/env bash
# MiniBatch 호스트에 데이터 폴더와 비밀 값 폴더를 만든다. 여러 번 실행해도 안전하다.
# 사용: MINIBATCH_DATA_DIR=... MINIBATCH_SECRETS_DIR=... ./scripts/host-prepare.sh
# - 비밀 값은 화면에 출력하지 않는다.
# - 이미 있는 비밀 값 파일은 덮어쓰지 않는다.
set -euo pipefail

: "${MINIBATCH_DATA_DIR:?MINIBATCH_DATA_DIR를 지정하세요}"
: "${MINIBATCH_SECRETS_DIR:?MINIBATCH_SECRETS_DIR를 지정하세요}"
command -v openssl >/dev/null || { echo "openssl 이 없습니다" >&2; exit 1; }

# 데이터 폴더. 컨테이너가 /data 로 붙인다
mkdir -p "$MINIBATCH_DATA_DIR"/{jobs,db,models,assets/fonts,assets/bgm,backups,logs}

# 비밀 값 폴더
# - youtube-token/ : job-api 가 갱신 토큰을 쓰는 폴더 (폴더째 읽기·쓰기로 붙인다)
# - providers/     : 영상 생성기·클라우드 LLM 의 API 키를 두는 폴더 (폴더째 읽기 전용으로 붙인다. 지금은 비어 있어도 된다)
mkdir -p "$MINIBATCH_SECRETS_DIR/youtube-token" "$MINIBATCH_SECRETS_DIR/providers"
chmod 700 "$(dirname "$MINIBATCH_SECRETS_DIR")" "$MINIBATCH_SECRETS_DIR" "$MINIBATCH_SECRETS_DIR/youtube-token" "$MINIBATCH_SECRETS_DIR/providers"

# 이 기기에서 만드는 비밀 값. 기기마다 달라도 된다
for f in n8n_encryption_key job_api_token; do
  path="$MINIBATCH_SECRETS_DIR/$f"
  if [ -s "$path" ]; then
    echo "있음(그대로 둠): $path"
  else
    ( umask 077; openssl rand -hex 32 > "$path" )
    echo "생성: $path"
  fi
done

# 사용자가 Google Cloud Console 에서 받아 넣는 파일 (작업 순서 1)
if [ -s "$MINIBATCH_SECRETS_DIR/youtube_client.json" ]; then
  echo "있음: youtube_client.json"
else
  echo "경고: youtube_client.json 이 없습니다. app 프로필을 올리기 전에 넣어야 합니다" >&2
fi

# 파일에만 600 (하위 폴더는 700 유지)
find "$MINIBATCH_SECRETS_DIR" -type f -exec chmod 600 {} +

echo "완료: $MINIBATCH_DATA_DIR, $MINIBATCH_SECRETS_DIR"
