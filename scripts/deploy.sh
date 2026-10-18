#!/usr/bin/env bash
# 개발 PC 에서 맥미니로 배포한다 (아키텍처 D34). 맥미니에는 git 도 빌드 도구도 두지 않는다.
#   ./scripts/deploy.sh <태그>      GitHub Actions 가 ghcr.io 에 올린 태그(커밋 7자리)로 배포
#   ./scripts/deploy.sh --sync      설정·중계기 파일만 맞춘다 (태그 그대로, 처음 구성 08 C1)
#   ./scripts/deploy.sh --rollback  바로 전에 배포한 태그로 되돌린다
# 하는 일: ① 인프라 저장소(.git·.env 제외)와 앱의 llm-bridge/ 를 맥미니 같은 경로로 복사
#          ② (태그가 있으면) .env 태그 변경 → compose pull → up -d → /healthz 확인
#          ③ 바뀐 것만 다시 시작: config/ → job-api, llm-bridge/ → Codex 중계기
# 비밀 값(.env, ~/.config/minibatch/secrets)은 맥미니에만 있고 보내지 않는다.
set -euo pipefail
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
APP="${MINIBATCH_APP_DIR:-$HOME/personal-projects/minibatch-app}"
TARGET="${MINIBATCH_DEPLOY_TARGET:-minibatch-mini}"
ARG="${1:?태그, --sync, --rollback 중 하나}"

remote() { ssh "$TARGET" "export PATH=\$HOME/.orbstack/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin; cd ~/personal-projects/minibatch-infra && $1"; }

# 커밋하지 않은 변경은 배포하지 않는다 (배포한 것 = 저장소에 있는 것)
for repo in "$INFRA" "$APP"; do
  if [ -n "$(git -C "$repo" status --porcelain -- . ':!*.md')" ] && [ "${FORCE:-}" != 1 ]; then
    echo "커밋하지 않은 변경이 있습니다: $repo (무시하려면 FORCE=1)" >&2; exit 1
  fi
done

TAG=""
case "$ARG" in
  --sync) ;;
  --rollback)
    TAG=$(remote "tail -n 2 .deploy-history 2>/dev/null | head -n 1 | awk '{print \$NF}'")
    [ -n "$TAG" ] || { echo "되돌릴 이전 태그가 없습니다" >&2; exit 1; } ;;
  *) TAG="$ARG" ;;
esac

echo "== 파일 맞추기 → $TARGET"
ssh "$TARGET" "mkdir -p ~/personal-projects/minibatch-infra ~/personal-projects/minibatch-app/llm-bridge"
CFG=$(rsync -a --delete --itemize-changes --exclude .git --exclude .env --exclude .deploy-history \
        "$INFRA/" "$TARGET:personal-projects/minibatch-infra/" | grep -E ' config/' || true)
BRIDGE=$(rsync -a --delete --itemize-changes --exclude __pycache__ \
        "$APP/llm-bridge/" "$TARGET:personal-projects/minibatch-app/llm-bridge/" || true)

if [ -n "$TAG" ]; then
  echo "== 이미지 $TAG"
  remote "grep -q '^MINIBATCH_APP_IMAGE_TAG=' .env"   # .env 는 맥미니에서 처음 한 번 만든다 (08 C2)
  remote "docker compose --profile app config --images | grep minibatch- | sed 's/:.*//' | sort -u | while read -r i; do docker pull -q \"\$i:$TAG\" >/dev/null; done"
  remote "sed -i '' 's/^MINIBATCH_APP_IMAGE_TAG=.*/MINIBATCH_APP_IMAGE_TAG=$TAG/' .env && echo \"\$(date '+%F %T') $TAG\" >> .deploy-history"
  remote "docker compose up -d && docker compose --profile app up -d"
fi
if [ -n "$CFG" ]; then
  echo "== 설정(config/)이 바뀌어 job-api 다시 시작"; remote "docker compose --profile app restart job-api"
fi
if [ -n "$BRIDGE" ]; then
  echo "== 중계기 다시 시작"; remote 'launchctl kickstart -k "gui/$(id -u)/com.minibatch.codex-bridge"'
fi

echo "== 확인"
for i in $(seq 1 12); do
  if remote "curl -sf http://127.0.0.1:8080/healthz >/dev/null"; then break; fi; sleep 5
done
remote "docker compose --profile app ps --format '{{.Service}} {{.Image}} {{.Status}}'; curl -s http://127.0.0.1:8080/healthz; echo; curl -s http://127.0.0.1:1235/healthz; echo"
