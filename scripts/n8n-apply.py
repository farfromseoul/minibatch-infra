#!/usr/bin/env python3
"""저장소의 n8n 워크플로 JSON 을 n8n 에 반영한다 (2026-10-18, 05 만난 오류: 화면 Import from File 이 노드를 덧붙임).

이름이 같은 워크플로가 있으면 그 ID 로 덮어쓰고(활성 상태 유지), 없으면 새로 만든다. 화면을 쓰지 않는다.
  ./scripts/n8n-apply.py                     이 PC 의 n8n 에 미리보기(바꾸지 않음)
  ./scripts/n8n-apply.py --apply             이 PC 의 n8n 에 반영
  ./scripts/n8n-apply.py --remote minibatch-mini --apply    Mac mini 의 n8n 에 (ssh)
하는 일: ① 워크플로·자격 증명 목록 읽기 ② JSON 에 기존 ID, 자격 증명 ID(이름으로), chatId(.env) 넣기
         ③ (--apply) 백업 export → import → 활성이던 것과 새로 만든 것 publish → n8n 재시작 → 노드 수 확인
자격 증명(`MiniBatch job-api`, `MiniBatch 텔레그램`)은 n8n 화면에서 먼저 만들어 둔다. 값은 이 스크립트가 다루지 않는다.
n8n 이 워크플로를 실행하는 중이면 재시작으로 끊긴다. 실행 중이 아닐 때 한다.
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

PLACEHOLDER = "CHAT_ID_를_여기에"
NEW_PUBLISH = {"MiniBatch 1", "MiniBatch 3", "MiniBatch 4", "MiniBatch 5"}  # 새로 만들 때 게시할 것 (2 검토 폼은 예비)
HOME = Path.home()


class N8n:
    def __init__(self, remote: str | None, container: str, infra_dir: str):
        self.remote, self.container, self.infra_dir = remote, container, infra_dir

    def _wrap(self, cmd: str) -> list[str]:
        if not self.remote:
            return ["sh", "-c", cmd]
        path = "export PATH=$HOME/.orbstack/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin; "
        return ["ssh", self.remote, path + cmd]

    def sh(self, cmd: str, stdin: bytes | None = None, check: bool = True) -> str:
        p = subprocess.run(self._wrap(cmd), input=stdin, capture_output=True)
        if check and p.returncode != 0:
            sys.exit(f"실패: {cmd}\n{p.stderr.decode(errors='replace')[-800:]}")
        return p.stdout.decode()

    def exec(self, cmd: str, stdin: bytes | None = None, check: bool = True) -> str:
        return self.sh(f"docker exec -i {self.container} sh -c {shlex.quote(cmd)}", stdin, check)

    def node_json(self, js: str) -> object:
        """n8n 컨테이너의 node 로 JS 를 돌려 JSON 출력 하나를 받는다"""
        return json.loads(self.exec("node -e " + shlex.quote(js)))


def clean(out: str) -> list[str]:
    return [l for l in out.splitlines() if l.strip() and not l.startswith("[n8n]") and "deprecat" not in l.lower()]


def workflows(n8n: N8n) -> dict[str, dict]:
    """이름 → {id, active, nodes}. 같은 이름이 둘이면 멈춘다(어느 쪽을 덮을지 모름)"""
    # 워크플로가 하나도 없으면 n8n 이 'No workflows found' 로 실패한다(새 n8n, 2026-10-18 맥미니). 빈 목록으로 본다
    n8n.exec("rm -rf /tmp/mb-list && mkdir -p /tmp/mb-list && (n8n export:workflow --all --separate --output=/tmp/mb-list/ >/dev/null 2>&1 || true)")
    data = n8n.node_json("const fs=require('fs');const d='/tmp/mb-list/';console.log(JSON.stringify("
                         "fs.readdirSync(d).map(f=>JSON.parse(fs.readFileSync(d+f))).map(w=>({id:w.id,name:w.name,"
                         "active:!!(w.active||w.activeVersionId),archived:!!w.isArchived,nodes:(w.nodes||[]).length}))))")
    out: dict[str, dict] = {}
    for w in data:
        if w["archived"]:
            continue
        if w["name"] in out:
            sys.exit(f"같은 이름의 워크플로가 둘 있다: {w['name']} ({out[w['name']]['id']}, {w['id']}). n8n 화면에서 하나를 정리한 뒤 다시")
        out[w["name"]] = w
    return out


def credentials(n8n: N8n) -> dict[str, str]:
    """이름 → ID. 값(암호화된 data)은 컨테이너 밖으로 꺼내지 않고 바로 지운다"""
    n8n.exec("n8n export:credentials --all --output=/tmp/mb-cred.json >/dev/null 2>&1")
    try:
        data = n8n.node_json("console.log(JSON.stringify(JSON.parse(require('fs').readFileSync('/tmp/mb-cred.json'))"
                             ".map(c=>({id:c.id,name:c.name}))))")
    finally:
        n8n.exec("rm -f /tmp/mb-cred.json", check=False)
    return {c["name"]: c["id"] for c in data}


def chat_id(n8n: N8n) -> str:
    """이미 있는 워크플로의 설정 노드 값을 먼저 쓰고, 없으면(새 n8n) .env 의 MINIBATCH_TELEGRAM_CHAT_ID"""
    found = n8n.node_json("const fs=require('fs');const d='/tmp/mb-list/';const ids=new Set();"
                          "for(const f of fs.readdirSync(d)){for(const n of (JSON.parse(fs.readFileSync(d+f)).nodes||[])){"
                          "const m=/chatId: '(-?\\d+)'/.exec((n.parameters||{}).jsCode||'');if(m)ids.add(m[1]);}}"
                          "console.log(JSON.stringify([...ids]))")
    if len(found) == 1:
        return found[0]
    if len(found) > 1:
        sys.exit("워크플로마다 chatId 가 다르다. n8n 화면에서 맞춘 뒤 다시")
    line = n8n.sh(f"grep -E '^MINIBATCH_TELEGRAM_CHAT_ID=' {n8n.infra_dir}/.env || true").strip()
    value = line.split("=", 1)[1].strip() if "=" in line else ""
    if not value.lstrip("-").isdigit():
        sys.exit(".env 의 MINIBATCH_TELEGRAM_CHAT_ID 가 숫자가 아니다 (08 C2)")
    return value


def prepare(src: Path, existing: dict[str, dict], creds: dict[str, str], chat: str) -> tuple[dict, str]:
    wf = json.loads(src.read_text(encoding="utf-8"))
    missing = sorted({c["name"] for n in wf["nodes"] for c in (n.get("credentials") or {}).values()} - set(creds))
    if missing:
        sys.exit(f"{src.name}: n8n 에 자격 증명이 없다: {', '.join(missing)} (08 D4 3번에서 먼저 만든다)")
    for n in wf["nodes"]:
        for c in (n.get("credentials") or {}).values():
            c["id"] = creds[c["name"]]
        code = n.get("parameters", {}).get("jsCode")
        if isinstance(code, str) and PLACEHOLDER in code:
            n["parameters"]["jsCode"] = code.replace(PLACEHOLDER, chat)
    if PLACEHOLDER in json.dumps(wf, ensure_ascii=False):
        sys.exit(f"{src.name}: chatId 자리표시가 코드 노드 밖에 남았다")
    cur = existing.get(wf["name"])
    wf["active"] = False
    if cur:
        wf["id"] = cur["id"]
        return wf, ("update-active" if cur["active"] else "update")
    wf.pop("id", None)
    return wf, "create"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--remote", help="ssh 대상 (예: minibatch-mini). 없으면 이 PC")
    ap.add_argument("--apply", action="store_true", help="실제로 반영 (없으면 미리보기)")
    ap.add_argument("--workflows", default=str(HOME / "personal-projects/minibatch-app/workflows"))
    ap.add_argument("--container", default="minibatch-n8n-1")
    ap.add_argument("--infra-dir", default="~/personal-projects/minibatch-infra")
    ap.add_argument("--only", help="파일 이름 일부로 고르기 (예: 1-produce)")
    a = ap.parse_args()

    n8n = N8n(a.remote, a.container, a.infra_dir)
    files = sorted(Path(a.workflows).glob("minibatch-*.json"))
    if a.only:
        files = [f for f in files if a.only in f.name]
    if not files:
        sys.exit(f"워크플로 JSON 이 없다: {a.workflows}")
    existing, creds, chat = workflows(n8n), credentials(n8n), chat_id(n8n)

    plan = []
    for f in files:
        wf, action = prepare(f, existing, creds, chat)
        cur = existing.get(wf["name"])
        before = f"{cur['nodes']}개" if cur else "-"
        print(f"{action:13s} {wf['name']}  노드 {before} → {len(wf['nodes'])}개" + (f"  (id {wf['id']})" if "id" in wf else ""))
        plan.append((f, wf, action))
    if not a.apply:
        n8n.exec("rm -rf /tmp/mb-list", check=False)
        print("\n미리보기다. 반영하려면 --apply")
        return

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = HOME / "minibatch-n8n-backups" / f"{a.remote or 'local'}-{stamp}"
    backup.mkdir(parents=True)
    for name, w in existing.items():
        out = n8n.exec(f"cat /tmp/mb-list/{w['id']}.json")
        (backup / f"{w['id']}.json").write_text(out, encoding="utf-8")
    print(f"백업: {backup}")

    n8n.exec("rm -rf /tmp/mb-apply && mkdir -p /tmp/mb-apply")
    for f, wf, _ in plan:
        n8n.exec(f"cat > /tmp/mb-apply/{f.name}", stdin=json.dumps(wf, ensure_ascii=False).encode())
        print(*clean(n8n.exec(f"n8n import:workflow --input=/tmp/mb-apply/{f.name} 2>&1"))[-1:])
    after = workflows(n8n)
    for f, wf, action in plan:
        w = after.get(wf["name"])
        if w is None:
            sys.exit(f"가져온 뒤 보이지 않는다: {wf['name']}")
        prefix = " ".join(wf["name"].split()[:2])
        if action == "update-active" or (action == "create" and prefix in NEW_PUBLISH):
            print(*clean(n8n.exec(f"n8n publish:workflow --id={w['id']} 2>&1"))[-1:])
    n8n.exec("rm -rf /tmp/mb-apply /tmp/mb-list", check=False)

    print("n8n 재시작")
    n8n.sh(f"docker restart {a.container} >/dev/null")
    time.sleep(15)
    final = workflows(n8n)
    bad = []
    for f, wf, _ in plan:
        w = final[wf["name"]]
        ok = w["nodes"] == len(wf["nodes"])
        bad += [] if ok else [wf["name"]]
        print(f"{'OK ' if ok else '다름'} {wf['name']}  노드 {w['nodes']}개  {'게시됨' if w['active'] else '게시 안 됨'}")
    n8n.exec("rm -rf /tmp/mb-list", check=False)
    if bad:
        sys.exit(f"노드 수가 다르다: {bad}. 백업 {backup} 을 같은 방법으로 되돌릴 수 있다")


if __name__ == "__main__":
    main()
