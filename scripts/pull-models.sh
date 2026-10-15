#!/usr/bin/env bash
# models.txt 의 LM Studio 모델을 받는다. 개발·운영 기기에서 같은 목록을 쓴다.
set -euo pipefail
cd "$(dirname "$0")/.."
LMS="${LMS:-$HOME/.lmstudio/bin/lms}"
grep -vE '^\s*(#|$)' models.txt | while read -r model fmt; do
  echo "받는 중: $model ($fmt)"
  "$LMS" get "$model" "--$fmt" -y
done
"$LMS" ls --llm
