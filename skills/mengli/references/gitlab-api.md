# mengli GitLab reference (glab 1.89, project `flip-id/flip-mobile`, id 1454265)

Run every command from the repo root so `:id` resolves. Helper scripts live in `~/.claude/skills/mengli/scripts/` (shortened to `$S` below).

| Need | Command |
|---|---|
| Current username (assignee) | `glab api /user \| python3 -c "import sys,json;print(json.load(sys.stdin)['username'])"` |
| Upload a file (video/screenshot) | `$S/gl-upload.sh <file>` → JSON `{markdown, url, full_path}`; embed `.markdown` in the description. (`glab api` can't send multipart, so the script uses curl with glab's token.) |
| Create MR | `glab mr create --title "<title>" --description "$(cat <desc.md>)" --source-branch <branch> --target-branch <base> --assignee <username> --remove-source-branch --yes` |
| Find MR for branch | `glab mr list --source-branch <branch> -F json` → `[0].iid` |
| MR diff | `glab mr diff <iid>` |
| Diff SHAs for inline comments | `glab api projects/:id/merge_requests/<iid>/versions` → `[0].base_commit_sha / head_commit_sha / start_commit_sha` (handled by `gl-inline.sh`) |
| Inline comment | `$S/gl-inline.sh <iid> <path> <new_line\|-> <old_line\|-> <body_file>` (added line → new_line only; removed → old_line only; context → both) |
| Discussions needing a response | `$S/gl-discussions.sh <iid>` (add `--all` to include handled ones) |
| Reply in a thread | `$S/gl-reply.sh <iid> <discussion_id> <body_file>` |
| Update MR description | `glab mr update <iid> --description "$(cat <desc.md>)"` |

## Comment and reply bodies
- At most two lines of plain text: the problem and the fix, or for a reply, what changed or why not. A ```suggestion block may follow for a small local fix.
- No prefix, severity tag, emoji, heading or list. Never mention AI, Claude, mengli, the pipeline or its files (`task.md`, `plan.md`).
- Reply examples:
  - `Fixed in a1b2c3d: moved the null check into the mapper.`
  - `Keeping this: the API always sends bank (BankMapper.test.ts:42).`
- mengli posts as you, so `gl-discussions.sh` treats a thread as handled once your account has the last note. A thread with a single note (a new comment, including mengli's own review comments) still needs a response.
- Use a temp file for bodies (`mktemp`), never inline multi-line strings in shell args.

## Forbidden (also denied in settings.json)
`glab mr merge`, `glab mr approve`, `glab mr close`, resolving threads on the reviewer's behalf, force-pushing.
