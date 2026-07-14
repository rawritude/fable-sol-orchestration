# Design decisions

Dated 2026-07-14. Each decision records the alternative considered and why it lost.

## D1 — Bash around `codex exec`, not MCP/daemon/framework
Alternatives: jinn (gateway daemon), aimee (multi-agent runtime), omp (multi-provider harness), an MCP wrapper.
Chosen because: zero moving parts to babysit; the harness's Bash tool already gives backgrounding, timeouts, and permission gating; every layer between Fable and Sol is a layer that can rot. The official plugin (app-server broker) covers the one thing raw exec lacks — job management for ad-hoc reviews.

## D2 — Prompt via temp file, result via `-o` file, stderr to log
Inline quoting breaks on real prompts; parsing the JSONL stream wastes context. stderr carries two things worth grepping (ANSI-coded `session id:`, final `tokens used`) and is otherwise thinking-noise.

## D3 — Sandbox tiers instead of `--yolo`
steipete's house default is `--yolo`; TRIP uses workspace-write/read-only. We take TRIP's posture: implementation gets `workspace-write` (+ opt-in network), reviews get `read-only`. Rationale: Sol output is generated code from a fallible model with tool access — confinement is cheap once the AppArmor profile exists, and it composes with (rather than fights) Claude Code's own permission classifier, which rightly refuses to spawn unsandboxed autonomous agents.
Addendum (2026-07-14): approvals and sandbox are independent axes. The visible/interactive lane pins `-a never` — bare interactive codex defaults to `-a on-request`, which stalls the pane on a mid-run escalation prompt the moment nobody is watching (first hit: a vitest suite needing a loopback bind). Measured the same day: `network_access=false` blocks `socket()` wholesale (seccomp EPERM), so port-binding proofs must opt into network at dispatch; with `-a never` there is no mid-run escalation path, which is the point.

## D4 — Fix the OS, not bypass it (bwrap AppArmor profile)
Ubuntu 24.04 ships `kernel.apparmor_restrict_unprivileged_userns=1`; codex spawns the system `/usr/bin/bwrap`, which then can't create user namespaces (`RTM_NEWADDR: Operation not permitted`). Alternatives: global sysctl flip (weakens the whole box), permission rule for `--yolo` (abandons sandboxing entirely). Chosen: a targeted profile granting `userns` to `/usr/bin/bwrap` — attaches to a stable path, survives codex/node upgrades, narrower than the global flip. Honest caveat (SECURITY.md): it is per-*binary*, not per-*caller*, so any local process can invoke bwrap for userns; acceptable on a single-user box, not on a shared one (use a group-constrained launcher there). Also relies on codex resolving to `/usr/bin/bwrap` rather than its bundled copy or the landlock path — hence the `bubblewrap` package prereq + resolved-path check in install.

## D5 — Review lane with a grep-able tag contract
Sol reviews plans before implementation and diffs after, ending with exactly one of `APPROVED` / `REQUEST_CHANGES` / `NEEDS_REWORK`. Anti-noise contract (don't flag intentional plan decisions, theoretical edge cases, style) plus implementer notes on resume rounds — this is what stops the "reviewer never signs off" divergence people hit. Convergence guard: max 3 rounds, then Fable arbitrates. Code reviews are pinned to a SHA so the diff can't shift mid-review.

## D6 — Review of Sol output is never delegated, and evidence is never trusted
Fable reads the full diff like a contributor PR and runs the tests itself; Sol's claims are advisory. (Cross-checked in the wild: a reviewer-runs-evidence bridge caught tests that fabricated their own assertions while every self-review passed.)

## D7 — Effort pin: high, escalate on evidence
Measured head-to-head (docs/EXPERIMENTS.md): xhigh bought +73% wall clock and +55% tokens for zero quality delta on a spec designed to punish shallow reasoning. Both efforts converged on the same architecture. So: `high` by default, `xhigh` only after a high run fails a verify round.

## D8 — Session-id-addressed resume, never `--last`
Parallel background delegations are the norm here; `--last` is a race. The session id is captured from the run's own stderr (strip ANSI first) and resumes are addressed explicitly. Resume inherits the original sandbox (verified).

## D9 — Two-strike takeover
After 2 failed fix rounds on the same issue, Fable stops delegating and does it directly. Delegation is an economics play, not an identity; the moment it costs more than typing, stop.

## D9b — Graceful degradation when Sol is unavailable
Distinct from D9 (a *quality* failure). If codex is usage-exhausted, logged out, or down, delegation fails at the transport, not the task. Detect it (nonzero exit + usage/quota/auth signal) and fall back *immediately* — don't burn the 2-strike budget or loop. Crucially, fall back by **swapping the implementer, not collapsing the roles**: spawn a Claude implementer subagent (Sonnet for routine, Opus for novel/hard — the standing tiering doctrine) and keep Fable as orchestrator/reviewer. Fable-does-everything is the wrong fallback — it's the single most expensive model in the stack and discards context separation. Only tiny edits (already Fable-direct) or genuine subagent-unavailability drop to Fable-direct. So Sol is an accelerator, never a hard dependency, and the degraded mode is still an orchestrated split — just intra-family and metered.

## D10 — Guardrails live on both sides
Fable-side: routing rule + skill keep secrets/MCP/prod/git actions out of delegation entirely. Sol-side: `~/.codex/AGENTS.md` standing rules (no commits, no secrets, no prod, structured report). Neither replaces a scoped prompt; both catch prompt-writing mistakes.

## Non-goals
- Model-vs-model tournaments, scorekeeping files, agent-to-agent chat channels (fun on Reddit, unmaintained state in practice).
- TRIP's phase state machine, per-project init rituals, ARCHI.md convention — over-engineered for this shop (owner ruling).
- The plugin's stop-time review gate — reviewing every turn is the wrong denominator; review at plan and ship boundaries instead.
