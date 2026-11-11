# Mengli
A task workflow for web, desktop, mobile, backend, CLI and library projects in Claude Code.

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
