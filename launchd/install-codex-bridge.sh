#!/usr/bin/env bash
# Codex 중계기 LaunchAgent 를 이 사용자 계정에 설치(또는 다시 설치)한다.
# 사용: ./launchd/install-codex-bridge.sh   (대체 모델은 models.txt 첫 줄에서 읽는다)
set -euo pipefail
cd "$(dirname "$0")"
DEST="$HOME/Library/LaunchAgents/com.minibatch.codex-bridge.plist"
MODEL=$(grep -vE '^\s*(#|$)' ../models.txt | head -1 | awk '{print $1}' | cut -d@ -f1)
test -f "$HOME/personal-projects/minibatch-app/llm-bridge/codex_bridge.py" || { echo "앱 저장소(llm-bridge)가 없습니다" >&2; exit 1; }
test -x /opt/homebrew/bin/codex || { echo "codex 가 없습니다 (B6)" >&2; exit 1; }
# 로그는 내장 디스크에: LaunchAgent 는 macOS 개인정보 보호(TCC) 때문에 외장 볼륨(/Data)에 못 쓴다 (2026-10-18 맥미니 실제: EX_CONFIG)
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/minibatch"
sed -e "s#__HOME__#$HOME#g" -e "s#__FALLBACK_MODEL__#$MODEL#g" com.minibatch.codex-bridge.plist.template > "$DEST"
plutil -lint "$DEST"
launchctl bootout "gui/$(id -u)" "$DEST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$DEST"
echo "설치: $DEST (대체 모델 $MODEL)"
