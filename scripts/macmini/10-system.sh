#!/usr/bin/env bash
# Mac mini 를 상시 운영 서버로 맞추는 시스템 설정. sudo 권한이 필요하다.
# 사용: ./scripts/macmini/10-system.sh [호스트이름]
set -euo pipefail
NAME="${1:-minibatch-mini}"

sudo -v

echo "== 호스트 이름: $NAME"
sudo scutil --set ComputerName "$NAME"
sudo scutil --set HostName "$NAME"
sudo scutil --set LocalHostName "$NAME"

echo "== 시간대"
sudo systemsetup -settimezone Asia/Seoul >/dev/null

echo "== 전원: 잠자기 끔, 정전 후 자동 켜짐, 네트워크로 깨우기"
sudo pmset -a sleep 0 disksleep 0 autorestart 1 womp 1 powernap 0
sudo pmset -a displaysleep 10

echo "== 업데이트: 확인·다운로드는 자동, macOS 설치는 수동"
SU=/Library/Preferences/com.apple.SoftwareUpdate
sudo defaults write $SU AutomaticCheckEnabled -bool true
sudo defaults write $SU AutomaticDownload -bool true
sudo defaults write $SU AutomaticallyInstallMacOSUpdates -bool false
sudo defaults write $SU ConfigDataInstall -bool true
sudo defaults write $SU CriticalUpdateInstall -bool true

echo "== 방화벽: 켬, 스텔스 모드(핑 등에 응답하지 않음)"
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
sudo $FW --setglobalstate on
sudo $FW --setstealthmode on

echo "완료. 확인: ./scripts/macmini/macmini-check.sh"
