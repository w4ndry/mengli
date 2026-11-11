#!/usr/bin/env bash
# Upload a file to the current repo's GitLab project; prints the JSON response
# ({alt, url, full_path, markdown}). Embed `.markdown` in the MR description.
# glab api can't send multipart, so this uses curl with glab's stored token.
# Usage: gl-upload.sh <file>   (run from the repo root)
set -euo pipefail
file="${1:?usage: gl-upload.sh <file>}"
[ -f "$file" ] || { echo "not a file: $file" >&2; exit 1; }

host="${MENGLI_GL_HOST:-gitlab.com}"
token="$(glab config get token --host "$host" 2>/dev/null || true)"
[ -n "$token" ] || { echo "no glab token for $host (run: glab auth login)" >&2; exit 1; }
project_id="${MENGLI_GL_PROJECT:-$(glab api projects/:id | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')}"

curl -sS --fail-with-body --request POST \
  --header "PRIVATE-TOKEN: ${token}" \
  --form "file=@${file}" \
  "https://${host}/api/v4/projects/${project_id}/uploads"
echo
