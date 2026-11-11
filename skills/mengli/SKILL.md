---
name: mengli
description: End-to-end project task workflow from prompt or ClickUp ticket through planning, implementation, adaptive QA and GitLab MR or GitHub PR review.
disable-model-invocation: true
---
# Mengli
Arguments: $ARGUMENTS
Run scripts/resolve-args.py with the raw arguments. Use repoRoot as the working repository. Read repository instructions, manifests, CI and relevant documentation. CLI overrides .mengli.json overrides bundled defaults; automatic discovery fills unspecified values. Config supports projectType, provider, remote, baseBranch, checks (named command strings), buildCommand, runCommand, qa and agent defaults. Never execute config commands before including them in the approved plan.
Detect provider from the selected remote (default origin); use gh/glab repository metadata for unfamiliar hosts. An explicit provider wins. If remote absent use none. Resolve base from remote HEAD then an existing main/master; ask if ambiguous. Detect project targets from manifests and changed areas; inspect subprojects in mixed repositories.
Read references/conventions.md. Never merge, approve, close, force push, reset hard, clean, push to protected/base branches or stage all paths. Never commit without approval. Do not attribute commits or review messages to an assistant.

## Workflow
Honor selected steps, preserving numbers 1–13 and letters a–m from the resolver. mr and review-mr also mean GitHub PR operations. Save versioned state in <repo>/.claude-work/<task-key>/state.json with repoRoot, target context, provider, base, branch, agents, completedSteps, skippedSteps, approval state, attempts and review {number,url}. Exclude .claude-work via git info exclude. Load legacy states, mapping mrIid/mrUrl and platform; rediscover context before reuse. Resume incomplete steps; explicit flags override saved values. Save logs after every step; failures are never completed. Always summarize stops with evidence and resume instructions.
1. task: merge optional ClickUp ticket, prompt, ACs and files into task.md, preserving origins and conflicts (user wins). Derive observable ACs if necessary. ClickUp is optional; no connector is needed for prompt-only work. Update ticket status only when authorized.
2. branch: require clean tracked files; use approved local naming or <type>/<slug>[-cu-ID]. Fetch base with fast-forward only when remote exists. Never overwrite user changes.
3. plan: invoke mengli-planner with absolute paths and resolved model/effort. Save plan.md including exact checks, QA target and evidence per AC, changed files and risks.
4. review-plan: invoke mengli-plan-reviewer, revise verified findings up to configured rounds. Present concrete plan and ask approval before implementation. Existing unapproved plans also require approval.
5. implement: follow approved plan and repository conventions; run discovered/configured checks. Fix failures up to configured rounds. Verify suspected pre-existing failures on isolated base worktree. Stop if unresolved.
6. review-code: invoke mengli-code-reviewer; verify findings, fix valid issues and rerun checks; at most two rounds.
7. qa: read references/qa.md; invoke mengli-qa with project context and approved commands. Save assertion evidence per AC; fix and replay within configured limits.
8. record: record demo when relevant and supported; otherwise log why skipped. Always write mini-review.md with change, reason, test instructions, checks and evidence.
9. push: stage explicit changed paths, show staged diff summary and exact commit message; obtain approval before EVERY commit. Push feature branch only. Provider none defaults to local results; explicitly requested publication without a provider is a prerequisite error.
10. mr: use existing review request or create one using provider reference and local template. Save neutral review number/url. Include only verified claims and available evidence.
11. review-mr: invoke mengli-mr-reviewer with provider, review number, base and absolute task/repo paths. Post verified inline findings only when publication/review is authorized.
12. fix: read provider discussions, verify issues, fix legitimate ones, rerun relevant checks/QA, request commit approval, push then reply with SHA. Explain rejected findings with evidence. Never resolve threads. One pass.
13. done: report branch, review URL, completed/skipped/stopped steps, checks and AC statuses. Do not mark blocked or failed work successful.

Prerequisites: implementation needs task and an approved plan; code review needs diff; QA needs ACs and runnable tooling; publication needs pushed branch; review/fix needs open MR/PR. Check before executing selected steps. Infer missing task read-only where possible; otherwise stop with missing producer step. No provider skips default publication steps with recorded reasons.
