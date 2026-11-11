#!/usr/bin/env python3
"""Parse /mengli arguments into a resolved run config (JSON on stdout).

Usage: resolve-args.py '<raw $ARGUMENTS string>'
Exit 2 with {"error": ...} on invalid input.
"""
import json
import os
import re
import shlex
import sys

HOME = os.path.expanduser("~")
SKILL_DIR = os.path.join(HOME, ".claude/skills/mengli")
AGENTS_DIR = os.path.join(HOME, ".claude/agents")

STEPS = [
    "task", "branch", "plan", "review-plan", "implement", "review-code",
    "qa", "record", "push", "mr", "review-mr", "fix", "done",
]
AGENT_KEYS = {
    "planner": "mengli-planner",
    "plan-reviewer": "mengli-plan-reviewer",
    "code-reviewer": "mengli-code-reviewer",
    "qa": "mengli-qa-simulator",
    "mr-reviewer": "mengli-mr-reviewer",
}
MODELS = ["sonnet", "opus", "haiku", "fable"]
EFFORTS = ["low", "medium", "high", "xhigh", "max"]
CLICKUP_URL = re.compile(r"app\.clickup\.com/t/(?:\d+/)?([A-Za-z0-9]+)")
CLICKUP_ID = re.compile(r"^(?:CU-|#CU-)?([a-z0-9]{7,14})$", re.IGNORECASE)


def fail(msg):
    print(json.dumps({"error": msg}, indent=2))
    sys.exit(2)


def step_index(token):
    t = token.strip().lower()
    if t.isdigit() and 1 <= int(t) <= len(STEPS):
        return int(t) - 1
    if len(t) == 1 and "a" <= t <= chr(ord("a") + len(STEPS) - 1):
        return ord(t) - ord("a")
    if t in STEPS:
        return STEPS.index(t)
    fail(f"Unknown step '{token}'. Use 1-13, a-m, or one of: {', '.join(STEPS)}")


def parse_steps(spec):
    out = set()
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        # range: a-f, 1-6, plan-qa (names contain '-', so try split points)
        if "-" in part and part.lower() not in STEPS:
            pieces = part.split("-")
            for i in range(1, len(pieces)):
                lo, hi = "-".join(pieces[:i]), "-".join(pieces[i:])
                try:
                    a, b = _quiet_index(lo), _quiet_index(hi)
                except ValueError:
                    continue
                if a > b:
                    a, b = b, a
                out.update(range(a, b + 1))
                break
            else:
                fail(f"Bad step range '{part}'")
        else:
            out.add(step_index(part))
    return out


def _quiet_index(token):
    t = token.strip().lower()
    if t.isdigit() and 1 <= int(t) <= len(STEPS):
        return int(t) - 1
    if len(t) == 1 and "a" <= t <= "m":
        return ord(t) - ord("a")
    if t in STEPS:
        return STEPS.index(t)
    raise ValueError(token)


def frontmatter(path):
    meta = {}
    try:
        with open(path) as f:
            text = f.read()
    except OSError:
        return meta
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    if not m:
        return meta
    for line in m.group(1).splitlines():
        if ":" in line and not line.startswith(" "):
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    return meta


def parse_model_effort(val, flag):
    model, _, effort = val.partition(":")
    model, effort = model.strip() or None, effort.strip() or None
    if model and model in EFFORTS and not effort:  # "--qa low" shorthand
        model, effort = None, model
    if model and model not in MODELS:
        fail(f"{flag}: model '{model}' not in {MODELS}")
    if effort and effort not in EFFORTS:
        fail(f"{flag}: effort '{effort}' not in {EFFORTS}")
    return {"model": model, "effort": effort}


def main():
    raw = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        tokens = shlex.split(raw)
    except ValueError as e:
        fail(f"Could not parse arguments: {e}")

    try:
        with open(os.path.join(SKILL_DIR, "config.json")) as f:
            config = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        fail(f"config.json unreadable: {e}")

    clickup_id, prompt_words, acs, files = None, [], [], []
    only = skip = None
    frm = to = None
    platform = base = None
    g_model = g_effort = None
    per_agent = {}

    i = 0

    def value():
        nonlocal i
        i += 1
        if i >= len(tokens):
            fail(f"{tokens[i - 1]} needs a value")
        return tokens[i]

    while i < len(tokens):
        t = tokens[i]
        if t == "--only":
            only = parse_steps(value())
        elif t in ("--skip", "--exclude"):
            skip = (skip or set()) | parse_steps(value())
        elif t == "--from":
            frm = step_index(value())
        elif t == "--to":
            to = step_index(value())
        elif t == "--platform":
            platform = value().lower()
            if platform not in ("ios", "android"):
                fail("--platform must be ios or android")
        elif t == "--base":
            base = value()
        elif t == "--model":
            g_model = value()
            if g_model not in MODELS:
                fail(f"--model must be one of {MODELS}")
        elif t == "--effort":
            g_effort = value()
            if g_effort not in EFFORTS:
                fail(f"--effort must be one of {EFFORTS}")
        elif t == "--ac":
            acs.append(value())
        elif t == "--file":
            p = os.path.expanduser(value())
            if not os.path.exists(p):
                fail(f"--file not found: {p}")
            files.append(os.path.abspath(p))
        elif t.startswith("--") and t[2:] in AGENT_KEYS:
            per_agent[t[2:]] = parse_model_effort(value(), t)
        elif t.startswith("--"):
            fail(f"Unknown flag {t}. Agent flags: {', '.join('--' + k for k in AGENT_KEYS)}")
        else:
            m = CLICKUP_URL.search(t)
            m2 = CLICKUP_ID.match(t)
            if clickup_id is None and not prompt_words and (m or (m2 and re.search(r"\d", t))):
                clickup_id = (m or m2).group(1).lower()
            else:
                prompt_words.append(t)
        i += 1

    prompt_text = " ".join(prompt_words).strip()

    # ---- steps
    selected = set(range(len(STEPS))) if only is None else set(only)
    if frm is not None:
        selected = {s for s in selected if s >= frm}
    if to is not None:
        selected = {s for s in selected if s <= to}
    if skip:
        selected -= skip
    selected.add(STEPS.index("done"))
    has_selection = any(x is not None for x in (only, skip, frm, to))

    # ---- agents: per-agent arg > global arg > config.agents > config.defaults > frontmatter
    defaults = config.get("defaults") or {}
    cfg_agents = config.get("agents") or {}
    agents = {}
    for key, name in AGENT_KEYS.items():
        fm = frontmatter(os.path.join(AGENTS_DIR, f"{name}.md"))
        resolved = {}
        for field in ("model", "effort"):
            g = g_model if field == "model" else g_effort
            for src, val in (
                ("arg:" + key, (per_agent.get(key) or {}).get(field)),
                ("arg:global", g),
                ("config.agents", (cfg_agents.get(key) or {}).get(field)),
                ("config.defaults", defaults.get(field)),
                ("frontmatter", fm.get(field)),
            ):
                if val:
                    resolved[field] = val
                    resolved[field + "Source"] = src
                    break
        agents[key] = {"subagent_type": name, **resolved}

    qa = config.get("qa") or {}
    platform = platform or qa.get("platform", "ios")

    out = {
        "clickupId": clickup_id,
        "promptText": prompt_text or None,
        "acs": acs,
        "files": files,
        "hasInput": bool(clickup_id or prompt_text or acs or files),
        "steps": [
            {"n": n + 1, "letter": chr(ord("a") + n), "name": STEPS[n]}
            for n in sorted(selected)
        ],
        "hasStepSelection": has_selection,
        "platform": platform,
        "platformConfig": qa.get(platform, {}),
        "env": qa.get("env", "staging"),
        "buildType": qa.get("buildType", "release"),
        "base": base or config.get("baseBranch", "master"),
        "agents": agents,
        "limits": {
            **(config.get("limits") or {}),
            "qaMaxAttempts": qa.get("maxAttempts", 5),
            "qaMaxHeals": qa.get("maxHeals", 2),
        },
    }
    if not out["hasInput"]:
        fail("Give at least one of: a ClickUp ID/URL, expectation text, --ac, or --file")
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
