#!/usr/bin/env bash
# Mac mini 운영 설정 점검. 실패 항목 수를 종료 코드로 돌려준다.
# 일부 항목은 sudo 가 필요해 처음에 한 번 비밀번호를 묻는다.
set -uo pipefail
cd "$(dirname "$0")/../.."
FAIL=0
ok()   { printf "  [통과] %s\n" "$1"; }
bad()  { printf "  [실패] %s\n" "$1"; FAIL=$((FAIL+1)); }
check() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }

sudo -v

DATA="${MINIBATCH_DATA_DIR:-$HOME/minibatch-data}"
SECRETS="${MINIBATCH_SECRETS_DIR:-$HOME/.config/minibatch/secrets}"

echo "== macOS"
check "호스트 이름 minibatch-mini" test "$(scutil --get LocalHostName)" = "minibatch-mini"
check "FileVault 꺼짐 (자동 로그인 전제)" sh -c 'fdesetup status | grep -q "Off"'
check "자동 로그인 사용자 = $(whoami)" test "$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null)" = "$(whoami)"
check "잠자기 끔" sh -c 'pmset -g | grep -qE "^ sleep +0"'
check "정전 후 자동 켜짐" sh -c 'pmset -g | grep -qE "^ autorestart +1"'
check "macOS 자동 설치 끔" test "$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates 2>/dev/null)" = "0"
check "방화벽 켬" sh -c '/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q enabled'
check "SSH 듣는 중" sh -c 'lsof -nP -iTCP:22 -sTCP:LISTEN | grep -q LISTEN || nc -z 127.0.0.1 22'
check "SSH 비밀번호 로그인 막힘" sh -c 'sudo sshd -T 2>/dev/null | grep -qi "^passwordauthentication no"'

echo "== OrbStack"
check "docker 연결 (OrbStack)" sh -c 'docker info --format "{{.OperatingSystem}}" | grep -qi orbstack'
MEM=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
check "컨테이너 메모리 상한 9GB 이하" test "$MEM" -gt 0 -a "$MEM" -le 9663676416
check "~/.zshenv 에 OrbStack 경로" grep -q '.orbstack/bin' "$HOME/.zshenv"

echo "== LM Studio"
check "LM Studio 서버 응답" curl -sf http://127.0.0.1:1234/v1/models
check "LM Studio 가 127.0.0.1 에서만 열림" sh -c '! lsof -nP -iTCP:1234 -sTCP:LISTEN | grep -qE "\*:1234|0\.0\.0\.0:1234"'
if [ -f models.txt ]; then
  while read -r m fmt; do
    case "$m" in ''|\#*) continue;; esac
    check "모델 있음: $m" sh -c "$HOME/.lmstudio/bin/lms ls --llm | grep -q '${m%@*}'"
  done < models.txt
fi

echo "== 폴더와 비밀 값"
check "데이터 폴더" test -d "$DATA/jobs" -a -d "$DATA/db"
check "DB 파일 있음" test -s "$DATA/db/minibatch.sqlite"
check "데이터 폴더가 홈과 다른 디스크(외장 NVMe)" test "$(stat -f %d "$DATA/")" != "$(stat -f %d "$HOME")"
check "백업 폴더 (내장)" test -d "${MINIBATCH_BACKUP_DIR:-$HOME/minibatch-backups}"
check "비밀 값 폴더 권한 700" test "$(stat -f %Lp "$SECRETS")" = "700"
check "youtube-token 폴더 700" test "$(stat -f %Lp "$SECRETS/youtube-token")" = "700"
check "providers 폴더 700" test "$(stat -f %Lp "$SECRETS/providers")" = "700"
check "providers.yaml 있음" test -s config/providers.yaml
while IFS= read -r f; do
  check "권한 600: ${f#$SECRETS/}" test "$(stat -f %Lp "$f")" = "600"
done < <(find "$SECRETS" -type f)

echo "== 서비스"
for port in 5678 8080; do
  check "포트 $port 는 127.0.0.1 에서만" sh -c "lsof -nP -iTCP:$port -sTCP:LISTEN | grep -q '127.0.0.1:$port' && ! lsof -nP -iTCP:$port -sTCP:LISTEN | grep -qE '\*:$port'"
done
check "job-api /healthz" curl -sf http://127.0.0.1:8080/healthz
check "백업 LaunchAgent 등록" launchctl print "gui/$(id -u)/com.minibatch.backup"
check "Codex 중계기 응답 (1235)" curl -sf http://127.0.0.1:1235/healthz
check "Codex 중계기 LaunchAgent 등록" launchctl print "gui/$(id -u)/com.minibatch.codex-bridge"
check "Codex ChatGPT 로그인" sh -c '/opt/homebrew/bin/codex login status 2>&1 | grep -qi "logged in"'

echo "== 디스크"
FREE_GB=$(df -g "$HOME" | awk 'NR==2{print $4}')
check "내장 여유 공간 50GB 이상 (현재 ${FREE_GB}GB)" test "$FREE_GB" -ge 50
DATA_FREE_GB=$(df -g "$DATA/" | awk 'NR==2{print $4}')
check "데이터 디스크 여유 공간 50GB 이상 (현재 ${DATA_FREE_GB}GB)" test "$DATA_FREE_GB" -ge 50

echo
if [ "$FAIL" -eq 0 ]; then echo "모두 통과"; else echo "실패 $FAIL 건"; fi
exit "$FAIL"
