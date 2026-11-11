# Mengli
A task workflow for web, desktop, mobile, backend, CLI and library projects in Claude Code.

## Getting started

1. Install from the Mengli directory:

   ```bash
   cd /path/to/mengli
   ./install.sh
   ```

2. Open a new Claude Code session from the target project's Git root:

   ```bash
   cd /path/to/project
   claude
   ```

3. Run a command inside Claude Code:

   ```text
   /mengli add a search page
   ```

Mengli asks for plan approval before implementation and approval before every commit. To publish to GitHub/GitLab, configure a remote and sign in with `gh`/`glab`. Without a provider, publication is skipped by default. QA uses available tooling and reports verification limits.

## Pipeline steps

| Number | Letter | Name | Purpose |
|---|---|---|---|
| 1 | a | `task` | Combine an optional ticket, prompt, files, and acceptance criteria |
| 2 | b | `branch` | Prepare a working branch |
| 3 | c | `plan` | Plan implementation and verification |
| 4 | d | `review-plan` | Review the plan and request approval before implementation |
| 5 | e | `implement` | Implement changes and run project checks |
| 6 | f | `review-code` | Review the diff, fix valid findings, and rerun checks |
| 7 | g | `qa` | Verify acceptance criteria with evidence |
| 8 | h | `record` | Record a demo when relevant and write a change summary |
| 9 | i | `push` | Request commit approval, commit explicit files, and push |
| 10 | j | `mr` | Create or update a GitLab MR / GitHub PR |
| 11 | k | `review-mr` | Post inline reviews on the MR/PR |
| 12 | l | `fix` | Respond to comments and fix valid findings |
| 13 | m | `done` | Report results, checks, and verification limits |

Use `--only` to select steps, `--skip` to exclude steps, and `--from`/`--to` to limit the range. Names, numbers, and letters are supported: `--only task,plan` is equivalent to `--only 1,3` or `--only a,c`. Ranges such as `--only a-f` are also supported. Steps always run in pipeline order; `done` is always included for the summary.

## Usage examples

```text
# Full workflow, subject to approvals and available tooling/provider
/mengli add a search page

# Task and planning only; no branch creation or implementation
/mengli add a search page --only task,plan

# Run through plan review, including branch creation
/mengli add a search page --to review-plan

# Implementation and code review; no QA, recording, or publication
/mengli add a search page --to review-code

# Full workflow without QA or recording; implementation/fix tests still run
/mengli add a search page --skip qa,record

# Skip automated tests and QA/demo; still run lint/typecheck when available
/mengli add a search page. Do not run automated tests during implementation or fixes; report tests as not run --skip qa,record

# Resume the same task from QA using existing artifacts
/mengli <same-task-input> --from qa
```

`--skip qa,record` skips only those two steps. Tests included in checks during implementation, code review, or fixes may still run. To skip all tests, give an explicit instruction in the prompt as shown above; there is no `--skip-tests` flag yet. Skipped tests must be reported as not run, never PASS. This instruction does not automatically disable server-side CI when pushing.

Selected steps still need inputs from earlier steps: implementation requires a task and an approved plan, QA requires acceptance criteria and tooling, and review/fix requires an open MR/PR. If inputs are missing, Mengli stops and explains the prerequisites. Skipping `record` also skips its demo/summary generation; available check results should still be included when publishing.

To resume, use the same task input or ClickUp ID. See `.claude-work/<key>/log.md` for the stop reason and next action; `--from <step>` reruns the workflow starting at that step.

## Configuration and integrations

Install with `./install.sh`; uninstall with `./install.sh --uninstall`. The installer links the skill and agents into ~/.claude. Start a new session after agent changes.

Run `/mengli build a search page`, `/mengli fix the desktop settings dialog --project-type desktop`, `/mengli fix Android login --platform android`, or `/mengli add API pagination --project-type backend` from a Git repo. ClickUp IDs, --ac and --file are optional inputs. Use --only plan or --to review-plan for planning; existing step numbers and letters remain supported.

Mengli discovers repository rules, checks, targets and default branch. Optional root `.mengli.json` overrides bundled defaults; flags override project config. Example:

```json
{"projectType":"web","provider":"github","baseBranch":"main","checks":{"test":"npm test"},"buildCommand":"npm run build","runCommand":"npm run dev","qa":{"platform":"web"}}
```

Platforms: auto, web, desktop, ios, android, headless. Providers: auto, gitlab, github, none. Auto provider uses the selected remote (origin by default). Agent model/effort and step selection flags remain available.

QA uses available project tools and records assertion evidence per acceptance criterion. Missing tools are reported as blocked/unverified. Video is optional; non-UI projects retain test output. Artifacts and reusable flows live inside the target repo's ignored .claude-work directory. Existing global Flip flows are no longer installed or used.

GitLab uses glab and GitHub uses gh. Existing review requests are reused. GitHub evidence requires an existing accessible URL; local artifacts are not uploaded elsewhere. Local projects skip publication by default.

Plans require approval before implementation, and every commit requires approval. Mengli never merges, approves or closes review requests, force pushes or resolves reviewer threads. Resume with the same task input; inspect .claude-work/<key>/log.md for stops. Legacy state is read with project context rediscovered.
