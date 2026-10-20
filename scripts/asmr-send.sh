#!/usr/bin/env bash
# ASMR 영상을 개발 PC 에서 맥미니 inbox 로 보낸다 (ASMR쇼츠 기획서).
#   ./scripts/asmr-send.sh             보낼 폴더(기본 ~/Movies/asmr-outbox)의 영상을 모두 보낸다
#   ./scripts/asmr-send.sh <파일>...    지정한 파일만 보낸다
# 이름 규칙: YYYYMMDD-NN_제목.mp4 (또는 .mov). 같은 이름의 .txt 가 있으면 설명으로 같이 보낸다.
# 맥미니에서는 .incoming/ 에 다 받은 뒤 한 번에 inbox/ 로 옮긴다 (1시간마다 확인하는 쪽이 반쯤 받은 파일을 보지 않게).
# 보낸 파일은 원래 폴더의 sent/ 로 옮겨 다시 보내지 않는다.
set -euo pipefail

TARGET="${MINIBATCH_DEPLOY_TARGET:-minibatch-mini}"
OUTBOX="${ASMR_OUTBOX:-$HOME/Movies/asmr-outbox}"
REMOTE="minibatch-data/asmr"  # 맥미니 홈 기준 (~/minibatch-data → /Data/minibatch-data)
NAME_RE='^[0-9]{8}-[0-9]{2}_.+\.(mp4|mov)$'
shopt -s nullglob nocaseglob nocasematch

if [ $# -gt 0 ]; then
  files=("$@")
else
  files=("$OUTBOX"/*.mp4 "$OUTBOX"/*.mov)
fi
[ ${#files[@]} -gt 0 ] || { echo "보낼 영상이 없습니다: $OUTBOX"; exit 0; }

send=()  # 설명(.txt)을 영상보다 앞에 둔다: inbox 로 옮길 때 설명이 먼저 도착하게
for f in "${files[@]}"; do
  base=$(basename "$f")
  if [[ ! "$base" =~ $NAME_RE ]]; then
    echo "건너뜀(이름 규칙 YYYYMMDD-NN_제목.mp4): $base" >&2
    continue
  fi
  txt="${f%.*}.txt"
  [ -f "$txt" ] && send+=("$txt")
  send+=("$f")
done
[ ${#send[@]} -gt 0 ] || { echo "이름 규칙에 맞는 영상이 없습니다" >&2; exit 1; }
names=$(for f in "${send[@]}"; do basename "$f"; done)

echo "== 맥미니 폴더 준비 → $TARGET"
ssh "$TARGET" "mkdir -p ~/$REMOTE/.incoming ~/$REMOTE/inbox ~/$REMOTE/uploaded ~/$REMOTE/published ~/$REMOTE/rejected"

# 같은 이름이 맥미니 어느 폴더에든 있으면 멈춘다 (덮어쓰기·중복 업로드 방지)
dup=$(printf '%s\n' "$names" | ssh "$TARGET" \
  "cd ~/$REMOTE && while IFS= read -r n; do for d in inbox uploaded published rejected; do [ -e \"\$d/\$n\" ] && echo \"\$d/\$n\"; done; done; true")
if [ -n "$dup" ]; then
  echo "맥미니에 같은 이름이 있어 보내지 않았습니다 (이름의 NN 을 바꾸세요):" >&2
  echo "$dup" >&2
  exit 1
fi

echo "== 보내기 (${#send[@]}개 파일)"
rsync -a --partial --progress "${send[@]}" "$TARGET:$REMOTE/.incoming/"

echo "== inbox 로 옮기기"
printf '%s\n' "$names" | ssh "$TARGET" \
  "cd ~/$REMOTE && while IFS= read -r n; do mv \".incoming/\$n\" \"inbox/\$n\"; done"

for f in "${send[@]}"; do
  mkdir -p "$(dirname "$f")/sent"
  mv "$f" "$(dirname "$f")/sent/"
done
echo "완료: $(printf '%s\n' "$names" | grep -civE '\.txt$') 편. 1시간 안에 텔레그램으로 업로드 승인 요청이 옵니다"
