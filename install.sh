#!/usr/bin/env bash
# Link this repo into ~/.claude so edits here are live immediately.
#
#   ./install.sh              link agents, skill, maestro library; merge permissions; install git hooks
#   ./install.sh --uninstall  remove the links and the permissions this script added
#
# Safe to re-run: existing real files are backed up to ~/.claude/backups/mengli-<timestamp>/
# before being replaced, and permission rules are tracked so removed rules get pruned.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE="${CLAUDE_HOME:-$HOME/.claude}"
STATE="$CLAUDE/mengli/.installed-permissions.json"
BACKUP="$CLAUDE/backups/mengli-$(date +%Y%m%d%H%M%S)"
MODE="${1:-install}"

log() { printf '  %s\n' "$*"; }

backup() { # move a real file/dir out of the way (symlinks are just removed)
  local target="$1"
  if [ -L "$target" ]; then
    rm "$target"
  elif [ -e "$target" ]; then
    mkdir -p "$BACKUP"
    mv "$target" "$BACKUP/"
    log "backed up $target -> $BACKUP/"
  fi
}

link() { # link <source in repo> <target in ~/.claude>
  local src="$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    return
  fi
  mkdir -p "$(dirname "$dst")"
  backup "$dst"
  ln -s "$src" "$dst"
  log "linked $dst -> $src"
}

prune_dangling() { # remove links in <dir> that point into this repo but no longer resolve
  local dir="$1"
  [ -d "$dir" ] || return 0
  for l in "$dir"/*; do
    [ -L "$l" ] || continue
    case "$(readlink "$l")" in
      "$REPO"/*) [ -e "$l" ] || { rm "$l"; log "removed stale link $l"; } ;;
    esac
  done
}

unlink_all() {
  for l in "$CLAUDE"/agents/* "$CLAUDE/skills/mengli" "$CLAUDE/mengli/maestro"; do
    [ -L "$l" ] || continue
    case "$(readlink "$l")" in "$REPO"/*) rm "$l"; log "unlinked $l" ;; esac
  done
}

merge_permissions() { # $1 = install|uninstall
  python3 - "$REPO/settings/permissions.json" "$CLAUDE/settings.json" "$STATE" "$1" "$HOME" <<'PY'
import json, os, sys
frag_path, settings_path, state_path, mode, home = sys.argv[1:6]
frag = json.load(open(frag_path))
want = {k: [r.replace("{{HOME}}", home) for r in frag.get(k, [])] for k in ("allow", "deny")}
prev = json.load(open(state_path)) if os.path.exists(state_path) else {"allow": [], "deny": []}
settings = json.load(open(settings_path)) if os.path.exists(settings_path) else {}
perm = settings.setdefault("permissions", {})
added = removed = 0
for k in ("allow", "deny"):
    rules = perm.setdefault(k, [])
    target = [] if mode == "uninstall" else want[k]
    # drop rules we installed before that are no longer wanted
    for r in prev.get(k, []):
        if r not in target and r in rules:
            rules.remove(r); removed += 1
    for r in target:
        if r not in rules:
            rules.append(r); added += 1
tmp = settings_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2); f.write("\n")
os.replace(tmp, settings_path)
if mode == "uninstall":
    if os.path.exists(state_path): os.remove(state_path)
else:
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    json.dump(want, open(state_path, "w"), indent=2)
print(f"  permissions: +{added} -{removed}")
PY
}

install_hooks() { # re-run install after pull/checkout so new files and permission changes apply
  local hooks="$REPO/.git/hooks"
  [ -d "$hooks" ] || return 0
  for h in post-merge post-checkout post-rewrite; do
    cat > "$hooks/$h" <<HOOK
#!/usr/bin/env bash
# installed by mengli install.sh
"$REPO/install.sh" >/dev/null
HOOK
    chmod +x "$hooks/$h"
  done
  log "git hooks: post-merge, post-checkout, post-rewrite -> install.sh"
}

if [ "$MODE" = "--uninstall" ]; then
  echo "mengli: uninstalling from $CLAUDE"
  unlink_all
  merge_permissions uninstall
  echo "done. (backups, if any, are in $CLAUDE/backups/)"
  exit 0
fi

echo "mengli: installing $REPO -> $CLAUDE"
chmod +x "$REPO"/skills/mengli/scripts/* "$REPO/install.sh"

for f in "$REPO"/agents/*.md; do
  link "$f" "$CLAUDE/agents/$(basename "$f")"
done
link "$REPO/README.md" "$CLAUDE/agents/README.md"
prune_dangling "$CLAUDE/agents"

link "$REPO/skills/mengli" "$CLAUDE/skills/mengli"
# QA artifacts belong to the target project, not the installation.
for old in "$CLAUDE/agents/mengli-qa-simulator.md" "$CLAUDE/mengli/maestro"; do
  if [ -L "$old" ]; then
    case "$(readlink "$old")" in "$REPO"/*) rm "$old" ;; esac
  fi
done
mkdir -p "$CLAUDE/mengli/build"

merge_permissions install
install_hooks
echo "done. Start a new Claude Code session to pick up new or renamed agents."
