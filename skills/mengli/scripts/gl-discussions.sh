#!/usr/bin/env bash
# List an MR's discussions that still need a response from mengli, as compact JSON.
# mengli posts as you (the glab user), so a thread needs a response when:
#   - it is not resolved, and
#   - it has a single note (a new comment, including mengli's own review comments),
#     or its last note is from someone else.
# Replying makes your note the last one, so re-running after replying is idempotent.
# Usage: gl-discussions.sh <mr_iid> [--all]
set -euo pipefail
iid="${1:?mr iid}"; mode="${2:-}"
me="$(glab api /user | python3 -c 'import sys,json;print(json.load(sys.stdin)["username"])')"
glab api --paginate --output ndjson "projects/:id/merge_requests/${iid}/discussions?per_page=100" |
MODE="$mode" ME="$me" python3 -c '
import json, os, sys
LEGACY_SUMMARY = "🤖 mengli review"  # summary notes from older runs need no reply
mode, me = os.environ["MODE"], os.environ["ME"]
out = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    notes = [n for n in d.get("notes", []) if not n.get("system")]
    if not notes:
        continue
    first, last = notes[0], notes[-1]
    resolvable = [n for n in notes if n.get("resolvable")]
    resolved = bool(resolvable) and all(n.get("resolved") for n in resolvable)
    awaiting = len(notes) == 1 or last["author"]["username"] != me
    needs = not resolved and awaiting and not first["body"].startswith(LEGACY_SUMMARY)
    if mode != "--all" and not needs:
        continue
    pos = first.get("position") or {}
    out.append({
        "discussion_id": d["id"],
        "path": pos.get("new_path") or pos.get("old_path"),
        "new_line": pos.get("new_line"),
        "old_line": pos.get("old_line"),
        "author": first["author"]["username"],
        "body": first["body"],
        "replies": [{"author": n["author"]["username"], "body": n["body"]} for n in notes[1:]],
        "resolved": resolved,
        "needs_response": needs,
    })
print(json.dumps(out, indent=2, ensure_ascii=False))
'
