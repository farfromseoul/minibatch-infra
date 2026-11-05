#!/bin/bash
# 맥미니 로그인(재부팅) 뒤 Tailscale 앱을 켜고, 연결이 꺼져 있으면 켠다 (2026-11-05: 재기동 뒤 앱은 떴는데 연결이 Stopped 였다).
# 로그인이 풀린 상태(NeedsLogin)면 사람이 로그인해야 하므로 기록만 남기고 끝낸다. 한 번만 돈다(RunAtLoad).
T=/Applications/Tailscale.app/Contents/MacOS/Tailscale
open -ga Tailscale 2>/dev/null || true
for i in $(seq 1 36); do   # 최대 3분: 앱·네트워크 확장이 뜰 때까지
  st=$("$T" status --json 2>/dev/null | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("BackendState",""))' 2>/dev/null)
  case "$st" in
    Running) echo "$(date '+%F %T') Tailscale Running"; exit 0 ;;
    Stopped) echo "$(date '+%F %T') Stopped → up"; "$T" up || true ;;
    NeedsLogin) echo "$(date '+%F %T') NeedsLogin: 맥미니에서 Tailscale 로그인 필요 (09 운영명령)"; exit 1 ;;
  esac
  sleep 5
done
echo "$(date '+%F %T') 3분 안에 Running 이 되지 않음 (마지막 상태: ${st:-응답 없음})"
exit 1
