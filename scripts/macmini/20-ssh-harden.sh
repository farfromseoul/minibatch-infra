#!/usr/bin/env bash
# SSH 비밀번호 로그인을 막고 키 로그인만 허용한다.
# 반드시 키 로그인이 되는 것을 확인한 뒤 실행한다.
set -euo pipefail

if [ ! -s "$HOME/.ssh/authorized_keys" ]; then
  echo "중단: ~/.ssh/authorized_keys 가 비어 있다. 키를 먼저 등록한다." >&2
  exit 1
fi

CONF=/etc/ssh/sshd_config.d/200-minibatch.conf
sudo tee "$CONF" >/dev/null <<'EOF'
# minibatch-infra 가 관리한다. 키 로그인만 허용한다.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
sudo chmod 644 "$CONF"

# 설정 문법 검사
sudo sshd -t
echo "적용 완료. 새 연결부터 반영된다. 지금 연결은 끊지 말고 다른 창에서 접속을 시험한다."
