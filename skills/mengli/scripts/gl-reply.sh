#!/usr/bin/env bash
# Reply to an existing MR discussion thread.
# Usage: gl-reply.sh <mr_iid> <discussion_id> <body_file>
set -euo pipefail
iid="${1:?mr iid}"; did="${2:?discussion id}"; body_file="${3:?body file}"
payload="$(mktemp)"
trap 'rm -f "$payload"' EXIT
python3 -c 'import json,sys;print(json.dumps({"body":open(sys.argv[1]).read()}))' "$body_file" >"$payload"
glab api --method POST "projects/:id/merge_requests/${iid}/discussions/${did}/notes" \
  -H "Content-Type: application/json" --input "$payload"
