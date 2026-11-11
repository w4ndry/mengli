#!/usr/bin/env bash
# Post an inline diff discussion on an MR.
# Usage: gl-inline.sh <mr_iid> <file_path> <new_line|-> <old_line|-> <body_file>
#   added line    -> new_line=N old_line=-
#   removed line  -> new_line=- old_line=N
#   context line  -> both set
# Prints the created discussion JSON (id, notes[0].id). Run from the repo root.
set -euo pipefail
iid="${1:?mr iid}"; path="${2:?file path}"; new_line="${3:?new_line or -}"; old_line="${4:?old_line or -}"; body_file="${5:?body file}"

versions="$(glab api "projects/:id/merge_requests/${iid}/versions")"
payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT

VERSIONS="$versions" python3 - "$path" "$new_line" "$old_line" "$body_file" >"$payload" <<'PY'
import json, os, sys
path, new_line, old_line, body_file = sys.argv[1:5]
v = json.loads(os.environ["VERSIONS"])[0]
pos = {
    "position_type": "text",
    "base_sha": v["base_commit_sha"],
    "head_sha": v["head_commit_sha"],
    "start_sha": v["start_commit_sha"],
    "new_path": path,
    "old_path": path,
}
if new_line != "-":
    pos["new_line"] = int(new_line)
if old_line != "-":
    pos["old_line"] = int(old_line)
print(json.dumps({"body": open(body_file).read(), "position": pos}))
PY

glab api --method POST "projects/:id/merge_requests/${iid}/discussions" \
  -H "Content-Type: application/json" --input "$payload"
