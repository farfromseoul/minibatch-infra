#!/usr/bin/env bash
# 로그인(재부팅) 뒤 Tailscale 자동 연결 LaunchAgent 설치(또는 다시 설치). 사용: ./launchd/install-tailscale-up.sh
set -euo pipefail
cd "$(dirname "$0")"
DEST="$HOME/Library/LaunchAgents/com.minibatch.tailscale-up.plist"
test -x /Applications/Tailscale.app/Contents/MacOS/Tailscale || { echo "Tailscale 앱이 없습니다" >&2; exit 1; }
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs/minibatch"
sed -e "s#__HOME__#$HOME#g" com.minibatch.tailscale-up.plist.template > "$DEST"
plutil -lint "$DEST"
launchctl bootout "gui/$(id -u)" "$DEST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$DEST"
echo "설치: $DEST"
