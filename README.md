# mengli — end-to-end task harness for flip-mobile

`/mengli` takes a task from ticket to reviewed MR in one command:

```
task → branch → plan → plan review → ✋ your approval → implement → code review
     → QA on simulator (Maestro) → demo video → ✋ your approval → commit & push → MR → MR review → fix comments → summary
```

It stops for your input only at **plan approval** and **before every commit** (plus a one-time question when no ClickUp ID was given). It **never merges**.

**This repo is the source of truth.** `install.sh` links it into `~/.claude/`, so edits here take effect right away. Nothing is added to the flip-mobile repo.

---

## Install / update

```bash
git clone git@gitlab.com:wandry.flip/mengli.git ~/Work/mengli
~/Work/mengli/install.sh
```

`install.sh` is safe to re-run. It:
- **links** these into `~/.claude/`:
  - `agents/*.md` → `~/.claude/agents/`, with this README as `~/.claude/agents/README.md`
  - `skills/mengli/` → `~/.claude/skills/mengli`
  - `maestro/` → `~/.claude/mengli/maestro`

  Any real files already there are moved to `~/.claude/backups/mengli-<timestamp>/` first.
- **merges** `settings/permissions.json` into `~/.claude/settings.json`. It remembers which rules it added (`~/.claude/mengli/.installed-permissions.json`), so a rule you delete from the fragment is removed on the next run. `{{HOME}}` expands to your home dir.
- **adds git hooks** (post-merge, post-checkout, post-rewrite) that re-run it, so a `git pull` applies new agents and permission changes automatically.
- `./install.sh --uninstall` removes the links and the permissions it added.

When edits take effect:

| You change | Takes effect |
|---|---|
| An existing agent, the skill, references, scripts, `config.json`, Maestro flows | Immediately, through the links. New agents need a new Claude Code session |
| Add or rename an agent file | Re-run `./install.sh` (or `git pull`; the hooks run it) |
| `settings/permissions.json` | Re-run `./install.sh` |

The QA agent writes new Maestro flows into `maestro/` inside this repo. Commit them so the flow library is versioned.

---

## Quick start

```bash
# Full run from a ClickUp ticket (iOS, staging release)
/mengli 86d4abcde

# Ticket + extra expectations typed in the prompt
/mengli 86d4abcde voucher chip must hide when amount < 10k --ac "review slider shows bank name"

# No ticket: expectations from a file and the prompt
/mengli --file claude-files/TASK_DESCRIPTION.md --ac "error toast appears on timeout"

# Safe first try: stops at plan approval, no code, no GitLab
/mengli 86d4abcde --only a-d
```

Before QA runs, have the **staging app logged in** on the simulator/emulator. If the app asks for a PIN, `export MENGLI_QA_PIN=…` in your shell. The PIN is never written to disk.

---

## Steps

Each step can be named by number, letter, or name.

| # | letter | name | Who | What |
|---|---|---|---|---|
| 1 | a | `task` | main | Fetch ClickUp task, set status to In Progress, merge ticket + prompt + files into `task.md` with numbered ACs |
| 2 | b | `branch` | main | `master` → `git pull --ff-only` → `<prefix>/<type>/<slug>-cu-<id>` |
| 3 | c | `plan` | `mengli-planner` | Implementation plan with ACs, changes, tests, QA script |
| 4 | d | `review-plan` | `mengli-plan-reviewer` | BLOCKER/SHOULD/NIT findings, up to 2 rounds, then **your approval** |
| 5 | e | `implement` | main | Code + tests. Runs `yarn lint`, `npx tsc --noEmit -p .`, and the stream tests |
| 6 | f | `review-code` | `mengli-code-reviewer` | Reviews the diff; valid findings are fixed |
| 7 | g | `qa` | `mengli-qa-simulator` + main | Builds the staging release, verifies each AC with Maestro, up to 5 attempts |
| 8 | h | `record` | main | Records the demo video and writes `mini-review.md` |
| 9 | i | `push` | main | Shows the staged files and message for your approval, commits the listed paths only, then `git push -u` |
| 10 | j | `mr` | main | Uploads video/screenshots, then `glab mr create` with the repo template |
| 11 | k | `review-mr` | `mengli-mr-reviewer` | Posts short inline comments on the MR (no summary note) |
| 12 | l | `fix` | main | Handles each comment: fix (each commit needs your approval) + `Fixed in <sha>`, or a reply with the reason |
| 13 | m | `done` | main | Summary + MR link (always runs) |

---

## Flags

| Flag | Example | Meaning |
|---|---|---|
| *(first token)* | `86d4abcde`, `CU-86d4abcde`, ClickUp URL | Ticket (optional, must come first) |
| *(free text)* | `chip must hide under 10k` | Expectations / ACs |
| `--ac` | `--ac "slider shows bank name"` | One AC (repeatable) |
| `--file` | `--file ~/Desktop/figma.png` | Spec or screenshot input (repeatable; md, txt, images) |
| `--only` | `--only a-f`, `--only 1-6`, `--only plan,qa` | Run only these steps |
| `--skip` / `--exclude` | `--skip g,h` | Run everything except these |
| `--from` / `--to` | `--from qa --to mr` | Run a range of steps |
| `--platform` | `--platform android` | QA platform (default `ios`) |
| `--base` | `--base develop` | Base/target branch (default `master`) |
| `--model` / `--effort` | `--model sonnet --effort medium` | Applies to **all** agents |
| `--<agent>` | `--qa haiku:low`, `--planner :max`, `--code-reviewer opus` | Model and/or effort for **one** agent |

Agent keys: `planner`, `plan-reviewer`, `code-reviewer`, `qa`, `mr-reviewer`.
Models: `sonnet | opus | haiku | fable`. Efforts: `low | medium | high | xhigh | max`.

**Precedence** (first match wins): per-agent flag → `--model`/`--effort` → `config.json` `agents.<key>` → `config.json` `defaults` → the agent file's frontmatter. The resolved values are written to the run's `log.md`.

The implement and fix steps run in your main session, so they use your session's `/model` and `/effort`.

### Examples

```bash
/mengli 86d4abcde --only a-f                # local work only, nothing pushed
/mengli 86d4abcde --skip g,h                # no simulator, no video
/mengli 86d4abcde --only qa --platform android
/mengli 86d4abcde --only review-mr,fix      # MR already open, just the review loop
/mengli 86d4abcde --qa sonnet:medium --planner :xhigh
```

When a step you picked needs something a skipped step would have produced, mengli:
- **works around it** when it can (e.g. uses the current branch, or reads the task without changing its ClickUp status),
- **reuses** what an earlier run left in `.claude-work/<key>/`, or the MR already open for the branch,
- **stops before doing anything** when it can't, and names the step that produces the missing input (e.g. `--only mr` on an unpushed branch).

---

## Agents (`agents/`)

| File | Default model / effort | Tools | Job |
|---|---|---|---|
| `mengli-planner.md` | opus / max | Read, Grep, Glob, Bash (read-only), ClickUp get_task | Writes `plan.md`: ACs, root cause/approach, changes, reuse, tests, QA script, risks |
| `mengli-plan-reviewer.md` | opus / high | Read, Grep, Glob | Checks the plan against the task and code; `Verdict: APPROVE \| REVISE` |
| `mengli-code-reviewer.md` | opus / high | Read, Grep, Glob, Bash (git only) | Reviews the branch diff for bugs, missed ACs, test gaps, conventions |
| `mengli-qa-simulator.md` | sonnet / high | all except Edit/NotebookEdit (mobile-mcp, maestro) | `discover`: find paths, write Maestro flows, verify ACs. `heal`: repair a broken nav flow. Never edits app code |
| `mengli-mr-reviewer.md` | opus / high | Read, Grep, Glob, Bash (glab) | Posts inline comments of at most two lines; never approves or merges |

These agents are meant to be called by `/mengli`, which passes them absolute paths and the resolved model/effort. You can also run one on its own for debugging, as long as you give it the same inputs (see each file's "Inputs" section).

---

## QA: explore once, replay with Maestro

1. **Build**: QA always tests a **staging release** build of the branch. The JS bundle is built into the app, so there is no Metro.
   - iOS: `xcodebuild` with scheme `FlipAppStaging` and configuration `Staging` for the simulator, then `simctl install`.
   - Android: `yarn build_android_staging_release`, then `adb install -r`.
   - Both install the app as `id.flip.staging`. A build is reused when the code hasn't changed.
2. **Discover** (attempt 1): for each AC's screen, the QA agent checks the flow library. When the screen isn't there, it finds the path with mobile-mcp and **saves it as a Maestro flow**: `~/.claude/mengli/maestro/subflows/nav-to-<screen>.yaml`. Flows select by `testID` first and never by coordinates.
3. **Replay** (attempts 2–5): after each fix, mengli rebuilds and runs `maestro test`. This takes seconds and needs no agent.
   - An assertion failure means an app bug: fix and replay.
   - A navigation failure means the flow is stale: the QA agent runs in `heal` mode, which doesn't count as an attempt (max 2).
4. Still failing after 5 attempts: mengli **stops and reports**.

The library grows with every task, so later tasks that reach the same screens skip discovery. Flows work on both platforms because RN `testID` maps to the iOS accessibilityIdentifier and the Android resource-id.

---

## Files

```
~/Work/mengli/                      (this repo)            linked to
├── README.md                       ← this file            ~/.claude/agents/README.md
├── install.sh                      ← link + merge + hooks
├── agents/
│   └── mengli-*.md                 ← 5 subagents          ~/.claude/agents/mengli-*.md
├── skills/mengli/                                         ~/.claude/skills/mengli
│   ├── SKILL.md                    ← orchestrator (/mengli)
│   ├── config.json                 ← persistent settings (see below)
│   ├── references/
│   │   ├── conventions.md          ← branch/commit/MR naming, checks, stream → test command
│   │   ├── qa.md                   ← build/install, Maestro conventions, QA loop, recording
│   │   └── gitlab-api.md           ← glab recipes
│   └── scripts/
│       ├── resolve-args.py         ← parses flags, steps, model/effort matrix
│       ├── gl-upload.sh            ← upload file to GitLab (curl + glab token)
│       ├── gl-inline.sh            ← post inline diff comment
│       ├── gl-reply.sh             ← reply in a discussion thread
│       └── gl-discussions.sh       ← list threads still needing a reply
├── maestro/                        ← flow library        ~/.claude/mengli/maestro
│   ├── index.json
│   └── subflows/
└── settings/permissions.json       ← allow/deny rules     merged into ~/.claude/settings.json

~/.claude/mengli/build/ios/         ← xcodebuild derived data (not in the repo)

<flip-mobile>/.claude-work/<key>/   ← per-task state (ignored via .git/info/exclude)
    log.md  state.json  task.json  task.md  inputs/  plan.md  plan-review-<n>.md
    code-review.md  maestro/  qa/attempt-<n>/  demo.mp4  mini-review.md  mr-description.md
```

### `config.json`

```json
{
  "baseBranch": "master",
  "defaults": { "model": null, "effort": null },
  "agents": { "planner": {}, "plan-reviewer": {}, "code-reviewer": {}, "qa": {}, "mr-reviewer": {} },
  "qa": {
    "platform": "ios", "env": "staging", "buildType": "release",
    "ios": { "scheme": "FlipAppStaging", "configuration": "Staging", "appId": "id.flip.staging", "device": null },
    "android": { "buildScript": "build_android_staging_release", "appId": "id.flip.staging", "avd": null },
    "maxAttempts": 5, "maxHeals": 2
  },
  "limits": { "planReviewRounds": 2, "checkFixRounds": 3 }
}
```

- Make a choice permanent: `"agents": { "qa": { "model": "sonnet", "effort": "medium" } }`.
- Pin a device: set `qa.ios.device` (simulator UDID) or `qa.android.avd`.
- Use a stream scheme: change `qa.ios.scheme` (e.g. `FlipDPStaging`).

---

## Conventions it follows

- **Branch**: `<prefix>/<type>/<slug>-cu-<id>`. The prefix is taken from your most recent own branch (currently `pnt`), not from the stream folder.
- **Commit**: one-line subject (a body only when it needs a sentence of context), no ticket ID, no AI attribution. It stages explicit paths only and asks you before committing.
- **MR title**: `[PNT] Fix|Feature|Test: <desc> #CU-<id>`. It uses `Fix Bug or UI Fix.md` or `Default.md`, links ClickUp, and assigns you. Neither the title nor the description mentions AI.
- **Checks**:
  - `yarn lint`
  - `npx tsc --noEmit -p .` (not `yarn tscheck`, which checks nothing)
  - `yarn unit_test:<stream> -- <paths> --maxWorkers=1` (the flag is left off scripts that already use `--runInBand`; DP uses `yarn test:dp`)
- **MR comments and replies**: at most two lines of plain text, no prefix. `gl-discussions.sh` treats a thread as handled when your account wrote its last note, so if you reply to a reviewer yourself, mengli leaves that thread alone.

---

## Safety

These rules come from `settings/permissions.json`. They are denied in `~/.claude/settings.json` and apply in every project:
- `glab mr merge`, `glab mr approve`, `glab mr close`
- `git push --force` / `-f`
- pushing to `master`, `develop`, `release/*`
- `git reset --hard`, `git clean`

Also:
- No code is written and nothing is pushed before you approve the plan.
- Nothing is committed until you approve the files and message.
- mengli never resolves review threads for the reviewer.
- A backup of the settings from before mengli was added is in `~/.claude/backups/settings.json.pre-mengli.*`.

---

## Resume & troubleshooting

- **Resume**: `/mengli <key>` continues after the last completed step, and returns to plan approval if you stopped there. `/mengli <key> --from <step>` re-runs from a given step.
- **Where it stopped**: `.claude-work/<key>/log.md` has the reason, evidence paths and the next action. `state.json` has `status` and `stopReason`.
- **Environment stops**: no device, build failure (last 50 log lines in `qa/build-<platform>.log`), or a login/OTP screen. These don't count as QA attempts.
- **First QA run**: `subflows/launch.yaml` is a bootstrap. The first discover run fills in the home-screen check and marks it verified in `index.json`.
- **New agents not showing**: run `./install.sh`, then start a new Claude Code session; agents are loaded at session start.
- **`/agents` warns about `README.md`**: delete the `~/.claude/agents/README.md` link. The README still lives in this repo.
