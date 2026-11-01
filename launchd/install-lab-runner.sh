#!/usr/bin/env bash
# 실습 리뷰 실험 실행기 LaunchAgent 설치(또는 다시 설치). 사용: ./launchd/install-lab-runner.sh  (실습리뷰쇼츠 실행계획 5단계)
set -euo pipefail
cd "$(dirname "$0")"
DEST="$HOME/Library/LaunchAgents/com.minibatch.lab-runner.plist"
CFG="$HOME/.config/minibatch-lab"
test -f "$HOME/personal-projects/minibatch-app/lab-runner/lab_runner.py" || { echo "앱 저장소(lab-runner)가 없습니다" >&2; exit 1; }
test "$(stat -f '%Lp' "$CFG/runner_token" 2>/dev/null)" = 600 || { echo "$CFG/runner_token 이 없거나 권한이 600 이 아닙니다 (1단계)" >&2; exit 1; }
test -x "$HOME/.orbstack/bin/docker" || { echo "docker(OrbStack)가 없습니다" >&2; exit 1; }
if [ "$(stat -f '%Lp' "$CFG/env" 2>/dev/null)" != 600 ]; then
  echo "주의: $CFG/env(실험 전용 Claude 토큰)가 아직 없습니다. 실행기는 뜨지만 실험은 로그인 오류로 실패합니다 (1단계)" >&2
fi
# 데이터 폴더 경로만 .env 에서 읽는다(비밀 값이 아닌 줄)
DATA=$(grep '^MINIBATCH_DATA_DIR=' ../.env | cut -d= -f2-)
test -n "$DATA" || { echo ".env 에 MINIBATCH_DATA_DIR 가 없습니다" >&2; exit 1; }
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/minibatch"
sed -e "s#__HOME__#$HOME#g" -e "s#__DATA_DIR__#$DATA#g" com.minibatch.lab-runner.plist.template > "$DEST"
plutil -lint "$DEST"
launchctl bootout "gui/$(id -u)" "$DEST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$DEST"
echo "설치: $DEST"
