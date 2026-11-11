---
name: mengli
description: End-to-end task harness for flip-mobile. Takes a ClickUp task and/or prompt/file expectations through task → branch → plan → plan review → (your approval) → implement → code review → simulator QA with Maestro → demo recording → (your approval) → commit/push → GitLab MR → MR review → fix comments → summary. Never merges. Supports running a subset of steps, iOS/Android, and per-agent model/effort.
argument-hint: "[clickup-id|url] [expectations…] [--ac \"<text>\"] [--file <path>] [--only steps] [--skip steps] [--from s] [--to s] [--platform ios|android] [--base branch] [--model m] [--effort e] [--<agent> model:effort]"
disable-model-invocation: true
---

# mengli — end-to-end task pipeline

Raw arguments: `$ARGUMENTS`

Run the pipeline in the flip-mobile repo (`/Users/FLP9EriWandri/Work/flip-mobile`). Work **autonomously** — you stop to ask only at the **plan approval gate**, the **commit approval gate** (before every commit), and the one-time ticket question when no ClickUp ID was given. Everything else: decide, act, log.

References (read when you reach the step that needs them):
- `~/.claude/skills/mengli/references/conventions.md` — branch/commit/MR naming, checks, stream test commands, work-dir layout
- `~/.claude/skills/mengli/references/qa.md` — build/install, Maestro flow library, QA loop, recording
- `~/.claude/skills/mengli/references/gitlab-api.md` — glab recipes + helper scripts
- Scripts: `~/.claude/skills/mengli/scripts/` (`resolve-args.py`, `gl-upload.sh`, `gl-inline.sh`, `gl-reply.sh`, `gl-discussions.sh`)

Hard rules for the whole run: **never merge, approve or close the MR; never force-push; never push to master/develop/release/*; never `git add -A`; never `git reset --hard` / `git clean`; never commit without the user's approval.** Never mention AI, Claude, mengli or any coding assistant in commits, the MR title/description, or MR comments. Follow AGENTS.md and the user's memory rules.

---

## Step 0 — Resolve arguments, state, selection

1. `python3 ~/.claude/skills/mengli/scripts/resolve-args.py "$ARGUMENTS"` → JSON run config. On `{"error"}` → print it with the usage below and stop.
2. **Ticket question**: if `clickupId` is null, ask once with AskUserQuestion: "Do you have a ClickUp ticket ID for this task?" — options: *No ticket* / (Other = type the ID). Use the answer.
3. **Key** = `clickupId`, else a kebab slug of the prompt text/file title. Work dir `W = <repo>/.claude-work/<key>/`. `mkdir -p W`; ensure `.claude-work/` is in `.git/info/exclude` (append once).
4. **State**: if `W/state.json` exists, load it. Without step-selection flags (`hasStepSelection: false`) → run only steps after the last in `completedSteps`. With flags → run exactly the selected steps. New flags for model/effort/platform override the saved ones; otherwise reuse the saved `agents`/`platform`.
   `state.json` shape:
   ```json
   {"key":"","clickupId":null,"branch":"","prefix":"","type":"","stream":"","base":"master",
    "platform":"ios","device":null,"appId":"id.flip.staging","agents":{},
    "completedSteps":[],"planApproved":false,"planRound":0,"qaAttempt":0,"qaHeals":0,
    "lastBuild":null,"mrIid":null,"mrUrl":null,"status":"running","stopReason":null}
   ```
5. **Pre-check prerequisites** for the selected steps (table below). Hard-missing → stop *before doing anything* and say which step produces the missing input.
6. Log to `W/log.md`: run header (time, args, selected steps with letters, platform, base) and the **agent matrix** (`key → model/effort (source)`).

| Step | Needs | If producer excluded |
|---|---|---|
| plan | task.md | soft: build task.md read-only (no ClickUp status change) |
| implement | branch, plan.md (approved) | branch: use current branch (must not be base/master/develop/release/*); no plan.md → work from task.md ACs (no gate) |
| review-code | diff vs base | hard if no diff |
| qa | ACs (plan.md or task.md), device | — |
| record | `W/maestro/ac-*.yaml` | hard if none exist |
| push | commits on branch | hard if nothing to push |
| mr | branch on remote | hard if not pushed (`git ls-remote --heads origin <branch>`) |
| review-mr, fix | open MR | look up with `glab mr list --source-branch <branch> -F json`; hard if none |

Pass resolved `model`/`effort` from the matrix to **every** Agent call (`subagent_type`, `model`, `effort`). Subagent prompts must include absolute paths (W, task.md, plan.md, repo root) — subagents have no memory of this conversation. The main-thread steps (implement, fixes) use this session's `/model` and `/effort`.

Usage text for errors:
```
/mengli [clickup-id|url] [expectations…] [--ac "<text>"]… [--file <path>]…
        [--only a-f|1-6|plan,qa] [--skip g,h] [--from qa] [--to mr]
        [--platform ios|android] [--base master]
        [--model sonnet|opus|haiku|fable] [--effort low|medium|high|xhigh|max]
        [--planner|--plan-reviewer|--code-reviewer|--qa|--mr-reviewer model:effort]
Steps: 1/a task  2/b branch  3/c plan  4/d review-plan  5/e implement  6/f review-code
       7/g qa  8/h record  9/i push  10/j mr  11/k review-mr  12/l fix  13/m done
```

After **every** step: append to `log.md` (`## <n>. <name> — <OK|STOP> <time>` + 1-5 bullet result), add it to `completedSteps`, save `state.json`. Steps always run in pipeline order.

---

## 1. task (a)
- If `clickupId`: `mcp__clickup__clickup_get_task` (include subtasks/checklists if offered) → save raw to `W/task.json`. Download image attachments into `W/inputs/` when the tool allows.
  - Status: read the task's list statuses (`mcp__clickup__clickup_get_list` or the task's `status` options); pick the one matching `/in progress/i`; `mcp__clickup__clickup_update_task` to it. If none matches, log it and continue.
- Copy each `--file` into `W/inputs/`. Read them (images too).
- Write `W/task.md`:
  ```
  # <title>
  ## Source: ClickUp   (name, url, description, checklist, attachments) | "None"
  ## Source: user prompt   (promptText + every --ac)  | "None"
  ## Source: files   (path → short summary / full text for md/txt) | "None"
  ## Acceptance criteria
  AC-1 [clickup] …
  AC-2 [prompt] …
  ## Conflicts   (ticket vs user input; user input wins) | "None"
  ```
  ACs must be observable. If the sources give no explicit ACs, derive them from the description and tag `[derived]`.

## 2. branch (b)
- `git status --porcelain --untracked-files=no` must be empty; otherwise STOP ("uncommitted changes in tracked files").
- Branch already in state and exists locally → `git checkout <branch>` and continue.
- Else: `git checkout <base> && git pull --ff-only`; derive prefix/type/slug per conventions.md (type may be refined after planning — branch name uses the best guess from task.md: bug → `fix`, else `feature`); `git checkout -b <branch>`. Save in state.

## 3. plan (c)
`Agent(subagent_type: mengli-planner, model, effort)` — prompt: "ultrathink. Plan this task." + paths to task.md, `W/inputs/`, repo root, base branch, and (on revision) the current plan + feedback. Save output verbatim to `W/plan.md`. Record `stream`/`type` from the plan's "Stream & Type" into state.

## 4. review-plan (d) + APPROVAL GATE
- Up to `limits.planReviewRounds` (2) rounds: `Agent(mengli-plan-reviewer)` with task.md + plan.md paths (+ previous review files) → save `W/plan-review-<n>.md`. If any BLOCKER/SHOULD: revise `plan.md` yourself (verify each finding against the code first; record rejected findings + reason at the bottom of plan.md under `## Review decisions`). Stop early on `Verdict: APPROVE` with no BLOCKER/SHOULD.
- **Approval gate** (runs after the last of plan/review-plan that executes; also before implement if an existing plan.md has `planApproved: false`):
  1. Print a compact digest: ACs, approach (3-6 bullets), files to change, tests, QA script per AC, risks, unresolved reviewer findings, conflicts, open questions, and the full path of `plan.md`.
  2. AskUserQuestion "Approve this plan?" — options: **Approve** (continue autonomously), **Request changes** (describe in Other / or edit plan.md yourself, then pick this), **Stop** (save and exit).
  3. Request changes → apply the notes (re-read plan.md in case the user edited it); if approach/files changed, one more plan-reviewer round; ask again. Stop → `status: "paused-at-approval"`, exit with how to resume (`/mengli <key>`).
  4. Approve → `planApproved: true`.
- No code is written and nothing is pushed before approval.

## 5. implement (e) — main thread
- Implement plan.md exactly (AGENTS.md, conventions.md code rules, Storybook rule). Add/update the tests the plan lists. Add testIDs the QA script needs.
- Checks (conventions.md): start `npx tsc --noEmit -p .` in the background; run `yarn lint`; run stream tests for changed/added test files. Fix and re-run until green, up to `limits.checkFixRounds` (3) rounds. A failure is pre-existing only if it's in a test/file the diff doesn't touch and fails the same way on the base branch (check with `git worktree add` of the base, never by stashing) → log it, don't fix.
- Still red → STOP with the failing output.

## 6. review-code (f)
`Agent(mengli-code-reviewer)` with base, task.md, plan.md. Save to `W/code-review.md`. For each finding: verify in code → fix (valid) or record "Rejected: <reason>" under it. After fixes re-run checks. If you fixed any BLOCKER, run one more review round (max 2 total).

## 7. qa (g) — read references/qa.md first
1. Device pre-flight for `platform` (default iOS). Save `device` in state.
2. Build & install the staging release (skip if `lastBuild` matches). Failure → environment STOP.
3. **Attempt 1 (discover)**: `Agent(mengli-qa-simulator, model, effort)` with `mode: discover`, platform, device, appId, task.md, plan.md, W, attempt 1. It reuses/creates library subflows and writes `W/maestro/ac-*.yaml`, then runs them.
4. Results: PASS → step done. `ENV_BLOCKED` / `NAV_IMPOSSIBLE` → STOP (environment) with its evidence. FAIL → loop:
   - **Attempts 2..qaMaxAttempts (5)** — you run them, no agent: fix the code for each failed AC (app bug) → re-run checks → rebuild/reinstall → `maestro test` the `W/maestro/` dir into `W/qa/attempt-<n>/` → parse report.xml (qa.md §6).
   - Nav failure in a library subflow → `Agent(mengli-qa-simulator, mode: heal, …)` with the failing flow/step/output (≤ qaMaxHeals, not counted as an attempt), then replay.
   - Still failing after the last attempt → STOP: per-AC status, last report, screenshots, what you tried.
5. Save `qaAttempt`, results table to log.

## 8. record (h)
Write `W/maestro/demo.yaml` (runFlow each `ac-*.yaml` in AC order), record per qa.md §7 into `W/demo.mp4` on the same device/build. Then write `W/mini-review.md`:
```
## What changed      — bullets, user-visible first, then technical
## Why               — root cause / reasoning (from plan)
## How to test       — preconditions + manual steps per AC (staging release, platform). No Maestro command or
                       flow YAML: their ~/.claude and .claude-work paths would show in the MR
## Evidence          — {{VIDEO}} and a screenshot table per AC ({{SHOT_AC_n}} placeholders, filled after upload)
## Checks            — lint / tsc / tests commands and results, QA attempts count
```

## 9. push (i)
- `git status` → stage **explicit** paths from the plan + files you changed (never `.claude-work/`, `claude-files/`, build outputs, `.env*`).
- Write the message per conventions.md (one-line subject, no ticket ID, no trailer or AI mention). Split into logical commits only if the plan calls for it.
- **Commit approval gate** — before every `git commit`, here and in step 12:
  1. Print `git diff --cached --stat` and the exact message.
  2. AskUserQuestion "Commit and push?" — options: **Commit & push**, **Stop**. Text typed in Other is a new message or a change to it: apply it, show it, ask again.
  3. Stop → leave the changes staged, `status: "paused-at-commit"`, log it, exit with how to resume (`/mengli <key> --from push`).
- Commit (heredoc message), then `git push -u origin <branch>`. Rejected (non-fast-forward) → `git pull --rebase origin <branch>` once, re-run tests, push again; still rejected → STOP.

## 10. mr (j)
- Existing MR for the branch → reuse it (update description instead of creating).
- Upload `demo.mp4` and the per-AC screenshots with `scripts/gl-upload.sh`; replace the placeholders in mini-review.md with the returned `markdown`.
- Build the description from the right template (conventions.md) with the mini review content filling its sections (Description/What is going on, Technical Notes/Caused by, Reference with the ClickUp link, Screenshot or Gif ← evidence, How Has This Been Tested ← how to test + checks; tick only true checklist items; Frozen Frames: "N/A" unless a critical screen changed — then say it was not measured). Nothing in the title or description mentions AI, Claude, mengli or `.claude*` paths. Write to `W/mr-description.md`.
- `glab mr create …` per gitlab-api.md (title per conventions.md, target = base, assignee = you). Save `mrIid`, `mrUrl`.

## 11. review-mr (k)
`Agent(mengli-mr-reviewer)` with mrIid, base, task.md, repo root. It posts inline comments only (no summary note). Log the comment list it returns.

## 12. fix (l)
- `scripts/gl-discussions.sh <iid>` → threads needing a response (human reviewers, GitLab Duo, and mengli's own review comments).
- For each, read the code and decide **legit or not**:
  - Legit → fix; batch related fixes; run checks (and replay Maestro flows touching the changed screen if QA ran); commit through the commit approval gate (step 9) and push; reply `Fixed in <short-sha>: <what changed>` via `gl-reply.sh`.
  - Not legit → reply with the reason and evidence, e.g. `Keeping this: <reason> (<file:line>)`.
  - Summary-style notes with nothing actionable → reply `Acknowledged: <one line>`.
- Replies follow the body rules in gitlab-api.md: at most two lines, no prefix.
- Stop at the gate → leave those fixes uncommitted, skip their `Fixed in` replies, `status: "paused-at-commit"`, exit with `/mengli <key> --only fix`.
- One pass. Never resolve threads.

## 13. done (m) — always runs
Final reply (also appended to log.md): MR link (if any), branch, steps run (with OK/skipped/STOP), AC table with QA result, checks, fixes made from MR comments (with SHAs), anything left for the user. Set `status: "done"`. **Do not merge.**

---

## STOP protocol
On any STOP: write `## <n>. <name> — STOP` with reason, evidence paths (logs, screenshots, report.xml) and the exact next action to `log.md`; set `status: "stopped"`, `stopReason` in state.json; reply with a short report and how to resume: `/mengli <key>` (continues after the last completed step) or `/mengli <key> --from <step>`.
