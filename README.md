# Fable ↔ Sol Orchestration

Cross-model, cross-CLI orchestration between **Claude Code (Fable)** and **Codex CLI (`gpt-5.6-sol`)** on one box. Fable thinks — specs, reviews, verifies, commits. Sol types — implementation, refactors, tests, bulk exploration — inside a real sandbox.

No framework, no daemon, no MCP bridge: skills + `codex exec` + files.

## Architecture

```
┌─ Claude Code session (Fable) ─────────────────────────────┐
│  routing rule (~/.claude/CLAUDE.md)                       │
│    │ implementation-shaped?                               │
│    ▼                                                      │
│  $codex-first skill                                       │
│    ├── implement lane:  codex exec --sandbox workspace-write
│    ├── review lane:     codex exec --sandbox read-only    │
│    │     (plan/code review, APPROVED/… tag contract)      │
│    ├── fleet lane:      N x codex exec in git worktrees   │
│    ├── verify panel:    3 x read-only reviewers           │
│    ├── follow-ups:      codex exec resume <session-id>    │
│    └── visible mode:    herdr pane (HERDR_ENV=1)          │
│                                                           │
│  Fable always: reads full diff, runs tests itself,        │
│  arbitrates review loops, owns all git/prod actions       │
└───────────────────────────────────────────────────────────┘
   Sol standing guardrails: ~/.codex/AGENTS.md
   Sandbox foundation:      /etc/apparmor.d/bwrap (userns grant)
   Ad-hoc reviews + bg jobs: official openai/codex-plugin-cc
```

## Components

| Path in repo | Installs to | What it is |
|---|---|---|
| `skills/codex-first/SKILL.md` | `~/.claude/skills/codex-first/` | The orchestration skill: routing table, invocation pins, sandbox tiers, review lane, verify loop |
| `skills/herdr/SKILL.md` | `~/.claude/skills/herdr/` | Visible transport — Sol in a sibling terminal pane (upstream: [ogulcancelik/herdr](https://github.com/ogulcancelik/herdr)) |
| `bin/sol-run` | `~/.local/bin/sol-run` | Allowlistable wrapper encoding the pinned invocation (0700 run dirs outside writable roots, flag pins, resume, `gc`); KEY=VALUE output contract incl. `AVAIL=hard_unavailable` for the fallback ladder |
| `codex/AGENTS.md` | `~/.codex/AGENTS.md` | Sol's standing guardrails: no commits/pushes, no secrets, no prod, FILES CHANGED/PROOF/RISKS report format |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Global routing rule making delegation the default |
| `system/apparmor/bwrap` | `/etc/apparmor.d/bwrap` | AppArmor userns grant for `/usr/bin/bwrap` — makes Codex's sandbox work on Ubuntu 24.04 |

## Model / effort policy

- Pin explicitly per invocation: `-m gpt-5.6-sol -c model_reasoning_effort="high" --enable fast_mode`. Never rely on `~/.codex/config.toml`.
- `high` is the measured default: xhigh cost +73% wall / +55% tokens for zero quality gain on a hard async-correctness spec (see `docs/EXPERIMENTS.md`). Escalate to `xhigh` only after a `high` run fails a verify round.
- `gpt-5.6-luna` as implementer (Sol reviews) is the community pattern — unbenchmarked here, candidate for a future experiment.

## Sandbox posture

- **Implementation:** `--sandbox workspace-write` (writes confined to repo + tmp; network off, opt-in via `-c sandbox_workspace_write.network_access=true`).
- **Review/exploration:** `--sandbox read-only`.
- **Interactive/visible runs (herdr):** pin `-a never` — approvals and sandbox are independent knobs; approvals-off keeps the sandbox intact, while the default `on-request` policy stalls an unattended pane on escalation prompts.
- **Never `--yolo`** — it drops approvals *and* the sandbox together.
- Network off blocks `socket()` entirely (seccomp EPERM), not just egress — port-binding test suites (vitest/playwright servers) need per-lot network opt-in at dispatch.
- Sol can sub-delegate: codex's `multi_agent` feature (stable, default-on) gives it `spawn_agent`/`wait_agent`/etc., and children verifiably inherit the session sandbox. Used for read-heavy fan-out only; parallel write lots use separate exec runs in separate git worktrees (see the skill's "Sol-side fan-out" section).
- Fleet lane: parallel implementation lots run in separate git worktrees (one `codex exec` per lot, verified no cross-contamination); merges are orchestrator-side and sequential; fleet width is bounded by review bandwidth.
- Verify panel: ship-gating reviews can fan out to 3 parallel read-only reviewers with distinct lenses (correctness / security / proof audit), 2-of-3 majority with fail-closed handling of confirmed P1/P2 findings.
- Requires the bwrap AppArmor profile on Ubuntu ≥23.10 (`apparmor_restrict_unprivileged_userns=1` otherwise kills every sandboxed spawn with `RTM_NEWADDR: Operation not permitted`).

## Install

```bash
./install.sh          # non-interactive by default; --apply to write, --force to overwrite differing files.
                      #   skills → managed files; CLAUDE.md/AGENTS.md → updated inside a delimited managed block
                      #   (your other content preserved). Backs up before touching anything.
```

Prereqs it checks: `codex` on PATH, `jq`, and (for the sandbox) the **system `bubblewrap` package** so codex resolves to `/usr/bin/bwrap` and not its bundled copy:

```bash
sudo apt install bubblewrap && command -v bwrap    # must print /usr/bin/bwrap
```

AppArmor step (sudo, once) — validate the profile parses before loading, and back up any existing one:

```bash
sudo apparmor_parser -Q --skip-cache system/apparmor/bwrap   # syntax check, no load
[ -f /etc/apparmor.d/bwrap ] && sudo cp /etc/apparmor.d/bwrap /etc/apparmor.d/bwrap.bak
sudo install -m 644 system/apparmor/bwrap /etc/apparmor.d/bwrap
sudo apparmor_parser -r /etc/apparmor.d/bwrap
```

Verify end to end: a `--sandbox workspace-write` run must write inside the workspace, be denied outside it, and NOT fail with `RTM_NEWADDR`. See `docs/SECURITY.md` for the trust boundary before pointing Sol at any repo you didn't write.

Optional complement — official plugin for ad-hoc reviews and background jobs:

```
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
```

Leave its stop-time review gate off (it reviews every turn, 900s timeout).

Optional, for prompt-free delegation from Claude Code: add `"Bash(sol-run:*)"` to `permissions.allow` in `~/.claude/settings.json`. Note the permission classifier rightly refuses to let the agent widen its own allowlist — add it yourself, or grant it explicitly in-session.

## Persistence & portability

**Same machine, switching Claude accounts:** nothing to do. Everything lives in machine-scoped paths (`~/.claude/skills`, `~/.claude/CLAUDE.md`, `~/.claude/plugins`, `~/.codex/`, `/etc/apparmor.d/bwrap`) — none keyed to the Claude account. Account switching only swaps `~/.claude/.credentials.json`. Codex auth is a separate ChatGPT login, untouched by Claude account changes.

**New machine:** `git clone` this repo → `./install.sh --apply` → the AppArmor sudo block above → install the plugin via `/plugin` (the one step the script can't automate) → `codex login` if codex isn't authed there yet.

**When Codex usage runs out:** the system degrades gracefully and *keeps the orchestrated split* — Fable detects the usage/auth failure and swaps the implementer to a Claude subagent (Sonnet for routine work, Opus for novel/hard) rather than doing everything itself, then reviews the diff as usual. It never blocks or loops. See "When Sol is unavailable" in the skill. ChatGPT usage limits are windowed and reset on their own.

## Credits / lineage

- Core pattern adapted from [steipete/agent-scripts](https://github.com/steipete/agent-scripts) `codex-first` ("Codex types, Claude thinks and verifies").
- Review-lane mechanics (tag contract, anti-noise list, implementer notes) adapted from [PiLastDigit/TRIP-workflow](https://github.com/PiLastDigit/TRIP-workflow) — deliberately without its state machine.
- Visible transport: [ogulcancelik/herdr](https://github.com/ogulcancelik/herdr).
- Ad-hoc review/background lane: [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).

Design decisions and their reasons: `docs/DESIGN.md`. Benchmarks: `docs/EXPERIMENTS.md`.
