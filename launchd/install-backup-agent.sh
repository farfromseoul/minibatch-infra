#!/usr/bin/env bash
# 백업 LaunchAgent 를 이 사용자 계정에 설치(또는 다시 설치)한다.
set -euo pipefail
cd "$(dirname "$0")"
DEST="$HOME/Library/LaunchAgents/com.minibatch.backup.plist"
mkdir -p "$HOME/Library/LaunchAgents"
sed "s#__HOME__#$HOME#g" com.minibatch.backup.plist.template > "$DEST"
plutil -lint "$DEST"
launchctl bootout "gui/$(id -u)" "$DEST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$DEST"
echo "설치: $DEST"
