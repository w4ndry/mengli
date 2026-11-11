# mengli conventions for flip-mobile

These come from AGENTS.md plus the user's standing preferences. When they conflict with the generic pipeline, these win.

## Branch
- Base: `config.json.baseBranch` (default `master`), or `--base`.
- Name: `<prefix>/<type>/<slug>-cu-<clickupId>`. With no ticket: `<prefix>/<type>/<slug>`.
  - `prefix` = the user's **team** prefix, not the stream folder. Take it from the most recent branch the user authored:
    `git for-each-ref --sort=-committerdate --format='%(refname:short) %(authoremail)' refs/heads | grep -i "$(git config user.email)" | head -1` → the part before the first `/`. (Currently `pnt`.)
  - `type`: `fix` (bug), `feature`, `test`, `chore`, `improvement` — from the plan's "Stream & Type".
  - `slug`: kebab-case, ≤ 60 chars, from the task title.
- Never commit to `master`, `develop` or `release/*`.

## Commit
- One-line subject: plain English, imperative, ≤ 72 chars. **No** ticket ID (`#CU-…`) and no `[PREFIX]` in commits.
- Add a body only when the change needs a sentence of context (one sentence, wrapped at 72).
- No AI attribution: no `Co-Authored-By` trailer, no mention of Claude, AI, mengli or any coding assistant.
- Ask the user before every commit (commit approval gate, SKILL.md step 9).
- Stage explicit paths (`git add <file> …`). Never `git add -A` / `git add .`. Never stage `.claude-work/`, `claude-files/`, build outputs, or `.env*`.

## MR
- Title: `[PREFIX] <Type>: <Short description> #CU-<clickupId>` — PREFIX = uppercased branch prefix (`[PNT]`), Type ∈ `Fix`, `Feature`, `Test`, `Chore`, `Improvement`. No ticket → drop the `#CU-` suffix.
  - DP stream exception: `[DP-xxxxxx] [DP] Fix: … #CU-…` when the ticket has a DP ID.
- Template: `Fix Bug or UI Fix.md` for fixes, `Default.md` for everything else (`.gitlab/merge_request_templates/`). Fill every section; replace `- [Clickup](#)` with `- [Clickup](https://app.clickup.com/t/3688330/<clickupId>)`; delete unused example tables; tick only checklist items that are actually true.
- Target: base branch. Assignee: the `glab api /user` username. `--remove-source-branch`.
- No AI attribution: nothing in the title or description mentions Claude, AI, mengli or a coding assistant, including `~/.claude/…` and `.claude-work/…` paths.

## Checks (step 5 and after every fix)
| Check | Command | Note |
|---|---|---|
| Lint | `yarn lint` | Lints files changed vs `origin/master` |
| Types | `npx tsc --noEmit -p .` | Run in background (minutes). **Not** `yarn tscheck` — it checks nothing |
| Tests | per stream, below | Target changed/added test files first, then the whole stream config if cheap |

Stream → test command (append `-- <paths> --maxWorkers=1` unless noted):
| Stream folder | Logic tests | UI tests |
|---|---|---|
| capt | `yarn unit_test:capt` | `yarn unit_test:capt-ui` (has `--runInBand` → **no** `--maxWorkers`) |
| com | `yarn unit_test:common` (`--runInBand` → no flag) | – |
| core | `yarn unit_test:core` | – |
| hc | `yarn unit_test:hc` (`--runInBand` → no flag) | – |
| ir | `yarn unit_test:ir` | – |
| kyc | `yarn unit_test:kyc` | – |
| px | `yarn unit_test:px` | `yarn unit_test:px-ui` |
| docter | `yarn unit_test:docter` | `yarn unit_test:docter-ui` |
| investment | `yarn unit_test:ive` | `yarn unit_test:ive-ui` (already `--maxWorkers=1` → no flag) |
| emoney | `yarn unit_test:emoney` | `yarn unit_test:emoney-ui` |
| saving | `yarn unit_test:saving` | `yarn unit_test:saving-ui` |
| insurance | `yarn unit_test:insurance` | `yarn unit_test:insurance-ui` |
| gold | `yarn unit_test:gold` | `yarn unit_test:gold-ui` |
| crypto | `yarn unit_test:crypto` | `yarn unit_test:crypto-ui` |
| lending | `yarn test:lending` | – |
| dp | `yarn test:dp` (**not** unit_test:dp) | `yarn test:dp:ui` |
| gap | `yarn unit_test:gap` (`--runInBand` → no flag) | – |
Never run `jest` directly. Re-check `package.json` if a script is missing — names drift.

## Code rules worth re-checking before commit
F_ base components / `@flip.id/mobile-design-system`; path aliases (no cross-folder relative imports); Zustand for new state (never Redux); no inline styles; testIDs on list items use `item.id` (never `${index}`); boolean props `isUse*`/`is*` (never bare `use*`); mappers emit `undefined` for absent nested objects; Storybook story for new/changed presentational components (`wiki/how_to_create_storybook.md`); 3–5 tests per file, mocks before imports (`wiki/testing_guide.md`).

## Work dir `.claude-work/<key>/` (repo root, ignored via `.git/info/exclude`)
```
log.md            timestamped step log
state.json        run state (see SKILL.md)
task.json         raw ClickUp task
task.md           merged task + numbered ACs
inputs/           copies of --file inputs
plan.md           approved plan
plan-review-<n>.md
code-review.md    findings + decisions
maestro/          ac-<n>.yaml, demo.yaml
qa/attempt-<n>/   report.xml, screenshots, logs; qa/build-<platform>.log
demo.mp4
mini-review.md    MR description body
```
