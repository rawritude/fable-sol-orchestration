---
name: codex-first
description: "Route implementation work to Codex CLI (Sol, gpt-5.6-sol); Claude (Fable) specs, reviews, verifies. Use for build-from-spec, refactors, migrations, bug fixes with repro, test writing, bulk exploration — or when the user says delegate to codex/sol."
---

# Codex First — Fable orchestrates, Sol implements

Claude Code sessions only. Codex/other harnesses: skip; never self-delegate.

Rationale: Fable tokens are metered; Codex (`gpt-5.6-sol`) is flat-rate and strong at raw code generation. Sol types, Fable thinks and verifies. Adapted from steipete/agent-scripts `codex-first`.

## Route

Delegate to Sol (default for hands-on work):

- implementation from a frozen spec; refactors; mechanical migrations
- bug fixes with a known repro; test writing; coverage fills
- CI fixes, dependency bumps, scripts/tooling
- bulk codebase exploration where raw reading ≫ the answer

Keep in Fable:

- design, API design, architecture, naming, UX judgment (taste/design calls stay with the orchestrator)
- tasks where writing the spec IS the work (ambiguity = design)
- tiny edits (~<20 lines, single obvious change) — delegation overhead loses
- anything needing session tools: MCP servers, browser/computer-use, claude.ai connectors
- anything touching `~/.secrets`, `.env` values, credentials
- production (prod-host ssh, deploy stack, deploys), DB migrations, protected-branch pushes — orchestrator-side per house rules  *(customize this line to your own infra)*
- ALL git commits/pushes/PRs — Sol never commits; Fable reviews then commits
- review of Sol output — never delegated, never skipped

Mixed task: Fable designs first, freezes spec, delegates build-out.
Heuristic: prompt reads as a work order → delegate; writing it forces decisions → design, Fable.

## Invoke (headless exec — default)

Prompt AND all output files go in a **unique private run dir OUTSIDE any sandbox writable root** — never fixed `/tmp/codex-*.md` paths. This is load-bearing security, not tidiness: the `-o` file is written by the *unsandboxed parent*, and workspace-write includes `/tmp`, so a predictable `-o` path lets a delegate pre-plant a symlink and make the parent overwrite any user-writable file (verified escape, 2026-07-14). Unique dirs also remove the parallel-run race.

```bash
umask 077
RUN="$(mktemp -d "${XDG_RUNTIME_DIR:-$HOME/.cache}/codex-run.XXXXXX")"  # 0700, NOT under /tmp workspace root
trap 'rm -rf "$RUN"' EXIT   # EXIT, not RETURN — RETURN doesn't fire at top-level script exit
cat >"$RUN/prompt" <<'EOF'
<goal, repo + key paths, constraints ("don't touch X"), non-goals, proof expected (exact test command), output shape>
EOF
codex exec -C <repo> \
  --ignore-user-config \
  --sandbox workspace-write \
  -c sandbox_workspace_write.network_access=false \
  -m gpt-5.6-sol \
  -c model_reasoning_effort="high" \
  --enable fast_mode \
  --json \
  -o "$RUN/result.md" - <"$RUN/prompt" >"$RUN/events.jsonl" 2>"$RUN/err"
SID="$(jq -r 'select(.type=="thread.started")|.thread_id' "$RUN/events.jsonl" | head -1)"  # robust session id
```

- `--ignore-user-config` skips `$CODEX_HOME/config.toml`, so config-defined MCP servers, extra writable roots, and network defaults don't leak in. It does NOT cover a standalone `~/.codex/hooks.json` — that still loads, so keep no untrusted hooks there (none by default). Pin sandbox/model/effort explicitly on top.
- Sandbox tiers: `workspace-write` for implementation (writes confined to repo + tmp, reads unrestricted), `read-only` for reviews/exploration. Enable network only per-task with `-c sandbox_workspace_write.network_access=true` (dep installs, or proofs that bind a port — next sentence); it grants direct unproxied egress, so keep it off by default and off for anything touching untrusted code. Network off blocks `socket()` wholesale (seccomp EPERM, verified 2026-07-14), not just egress — even loopback binds fail. Decide at dispatch: if the proof command spins up a local server (vitest/playwright server suites, BFF tests), the lot needs network on, else the proof hard-fails in-sandbox.
- Implementation-heavy lots: `gpt-5.6-luna` is the common flat-rate implementer pick in the wild (Sol reviews it); untested here — benchmark before making it the default.
- Effort: `high` is the default. Measured 2026-07-14 (tricky async-cache spec, generation mode): xhigh cost +73% wall / +55% tokens for zero quality gain — both swept an adversarial judge suite with the same architecture. Escalate to `xhigh` only after a `high` run fails a verify round on a correctness-heavy task; never preemptively.
- `--enable fast_mode` is the Fast-tier *feature gate* (`-c features.fast_mode=true`), not a per-request tier selector; it does not itself change the service tier. Harmless to keep on.
- Read the `-o` file for the result. `-o` does NOT suppress the final message on stdout, so redirect stdout to a file (`>"$RUN/events.jsonl"` with `--json`) to keep it out of context.
- Capture the session id from the `--json` `thread.started` event (above), never by scraping human-formatted stderr.
- Long runs: Bash `run_in_background`, read `-o` file on exit; don't kill quiet runs <30 min. (the EXIT trap fires when the launching shell exits; for detached background runs, read the result before that shell returns, or clean `$RUN` explicitly after.)
- Parallel independent tasks: each gets its own `$RUN` dir — never share paths.
- Outside a git repo add `--skip-git-repo-check`.
- **Trust boundary:** these tiers confine *writes*, not *reads* — a delegate reading an untrusted repo can read anything the invoking user can (`~/.ssh`, tokens) and codex auto-loads that repo's own `AGENTS.md` after the global one (closer wins). Only point Sol at repos you author or trust; for third-party code see SECURITY.md before delegating.

### When Sol is unavailable (usage exhausted / auth / down)

Delegation is an optimization, not a dependency — it never blocks. **Detecting** Sol is out:

- **Hard unavailability** — nonzero exit AND stderr/`-o` matches usage/quota/auth failure (`usage limit`, `rate limit`, `429`, `quota`, `insufficient_quota`, `not logged in`, `401`): Sol is tapped out or logged out. Do NOT retry-loop or spend the 2-strike quality budget on it. Tell the user once ("Codex usage exhausted / logged out — falling back; `!codex login` fixes auth, ChatGPT limits are windowed and reset").
- **Transient** — network/5xx/timeout blip, no usage signal: retry once; if it recurs, treat as hard.
- **Empty/short `-o` with zero exit**: not availability — that's a spec/prompt issue; iterate the prompt.
- codex has no stable CLI usage-query, so detect on the run. Optional cheap liveness probe before a big delegation: a trivial `echo ok` exec.

**Falling back — keep the orchestrator/implementer split; swap the implementer, don't collapse into Fable.** Fable is the most expensive model in the stack, so "Fable does everything" is both the costliest option and throws away context separation. Instead spawn a Claude implementer subagent (Agent tool, `model:` override) and review its diff exactly like Sol's — per the standing tiering doctrine (tiering: Sonnet = routine/legwork, Opus = novel build lots, Fable = orchestration/review). Ladder:

| Task | Sol available | Sol out |
|---|---|---|
| tiny (<~20 lines) | Fable direct | Fable direct (subagent overhead loses either way) |
| routine implementation / refactor / tests / migration | Sol | **Sonnet subagent** (`model: sonnet`), Fable reviews |
| novel / hard / correctness-critical build | Sol (xhigh if it fails a round) | **Opus subagent** (`model: opus`), Fable reviews |

Mechanics: `Agent` with `subagent_type: "claude"` (or `general-purpose`), `model: "sonnet"`|`"opus"`, prompt = the same frozen spec + prompt contract you'd have sent Sol; isolate with `isolation: "worktree"` if parallel. Fable still reads the full diff and runs tests itself — the review gate is unchanged, just intra-family (independent context, so still a real second pass; the cross-family adversarial bonus is what's lost while Sol is down, an acceptable degradation). Only drop to Fable-direct when even a subagent is overkill (the tiny row) or subagents are unavailable.

### Sandbox status

Working on Ubuntu 24.04 via `/etc/apparmor.d/bwrap` (AppArmor userns grant for `/usr/bin/bwrap`; codex spawns system bwrap). Verified: workspace writes OK, outside writes denied, network toggle works. If sandboxed spawns ever fail again with `RTM_NEWADDR: Operation not permitted`, check the profile is still loaded (`cat /sys/kernel/security/apparmor/profiles | grep bwrap`) — do NOT fall back to `--yolo`.

## Review lane (Sol reviews, Fable arbitrates)

Reviews run `--sandbox read-only` — Sol inspects, never edits. Same `$RUN`-dir invocation as above with the sandbox flag swapped to `read-only`.

- **Plan review** (before delegating a non-trivial build): Sol reviews the frozen spec. End the prompt with: `End with exactly one tag on its own line: APPROVED / REQUEST_CHANGES / NEEDS_REWORK`. Grep the tag; iterate the plan via resume.
- **Code review** (after Fable's own diff review, as a second opinion): pin the target — "review the diff of commit <SHA> against <base>" — so the diff can't shift mid-review.
- Anti-noise contract in every review prompt: do NOT flag intentional decisions recorded in the plan, theoretical edge cases that can't occur with real inputs, or style preferences; on resume rounds pass implementer notes (what changed and why) so addressed findings aren't re-litigated.
- Verdict handling is fail-closed: require exactly one tag after a clean process exit; missing / duplicated / malformed tag, or nonzero exit, is a review FAILURE, not an implicit pass. Findings are advisory input to Fable, never auto-applied.
- Convergence guard: max 3 rounds. After round 3, Fable dispositions *every* remaining finding explicitly; a confirmed P1/P2 correctness or security finding BLOCKS completion — only reviewer-noise or accepted-risk items may be "moved on."
- (Tag contract, anti-noise list, and notes channel adapted from PiLastDigit/TRIP-workflow — deliberately without its state machine. For ad-hoc reviews with background job management, the official `openai/codex-plugin-cc` plugin's `/codex:review` and `/codex:adversarial-review` cover the same ground.)

### Verify panel (ship-gating)

Use after Fable's own review, before commit, for correctness- or security-critical lots and integrated fleet diffs. Routine lots keep the single-reviewer default.

- Run 3 read-only reviewers in parallel, each backgrounded with its own `$RUN` dir and a distinct lens: (1) correctness, (2) security/trust-boundary, (3) proof audit — does the claimed proof actually demonstrate the spec's success criteria? Proof audit is static; Fable still reruns proofs itself. Diversity over redundancy: three different lens prompts, never three copies of one prompt.
- Same contracts as single reviews: SHA-pinned diff, anti-noise list, and exactly one fail-closed verdict tag per reviewer. A malformed or missing tag means that reviewer FAILED and counts as not-approved.
- Gate: 2/3 APPROVED passes the panel, **but any confirmed P1/P2 correctness or security finding from any reviewer must be explicitly dispositioned by Fable regardless of the vote**. Majority gates the verdict; findings stay fail-closed.
- Findings remain advisory input to Fable; the max-3-rounds convergence guard is unchanged. Flat-rate makes the 3x coverage free; parallel execution keeps elapsed time at ~1 review.

## Invoke (no-exec generation mode — best-effort, NOT enforced)

For greenfield/self-contained specs, or as a fallback if the sandbox regresses:

- Tell Sol its environment has no command execution or filesystem access, and demand deliverables as `===FILE: path===` … `===END===` blocks plus a RISKS section.
- Fable materializes the files, runs the tests, reviews.
- Honest caveat: this is prompt-only — `codex exec` still supplies tools and `read-only` still permits reads/commands, so it relies on model compliance, not enforcement. For a genuinely tool-free path use a plain API call with no tools. Don't call this "zero trust."

## Invoke (herdr visible mode)

When running inside Herdr (`test "${HERDR_ENV:-}" = 1`) and the user wants to watch: use `$herdr` skill mechanics instead of headless exec — split a sibling pane (`--no-focus`), rename it `sol`, `pane run <id> "codex --sandbox workspace-write -a never"` (swap to `--sandbox read-only` for review lots), wait for `idle`, then `pane run` the same frozen spec text, `herdr wait agent-status <id> --status done` (or `idle` if the user is watching the tab), and `pane read --source recent-unwrapped` for the result. Same prompt contract, same review gate — only the transport differs. Pin `-a never` explicitly: bare interactive codex defaults to `-a on-request`, and a mid-run escalation prompt stalls the pane indefinitely once nobody's watching (observed 2026-07-14: a sandbox-blocked vitest port bind produced exactly that stall). `-a never` keeps the sandbox on with approvals off — failures return to the model, same semantics as the exec lane. Since the model can't escalate mid-run, decide network access at dispatch (see sandbox tiers). Approvals and sandbox are independent knobs — never buy prompt-freedom with `--yolo`, which drops both.

- Immediately after launching codex in the pane, capture the session id from the newest rollout file under `~/.codex/sessions/YYYY/MM/DD/` whose first-line meta matches the repo cwd. Capture it **before launching any other codex** or the "newest" heuristic races.
- After `herdr wait agent-status <id> --status done` and `pane read --source recent-unwrapped` has captured the result, close the pane with `herdr pane close <id>`. This is lossless: edits are already on disk in the repo, and codex persists the thread incrementally to `~/.codex/sessions` rollout files, so it remains resumable headless with `codex exec resume "$SID"` after the pane is gone.
- Never close a pane whose agent status is `blocked` or `unknown` — inspect it with `pane get` / `pane read` first. A finished pane left open is stale state on the user's screen; close it once the result is captured.
- User-level complement (manual/interactive codex outside these lanes): `approval_policy = "on-request"` + `approvals_reviewer = "auto_review"` in `~/.codex/config.toml` routes escalation requests to a reviewer agent (Claude-classifier-style) instead of a human prompt, with a local `[auto_review]` policy; a circuit breaker (3 consecutive / 10-in-50 denials) can still surface to the human. The orchestrated lanes deliberately do NOT rely on it: they pin `--ignore-user-config` + `-a never` and make host-access decisions at dispatch — an LLM auto-approving sandbox escapes is acceptable for supervised interactive use, not for autonomous lots.

## Sol-side fan-out (multi-agent — verified 2026-07-14)

codex-cli 0.144.4 ships a stable, default-on `multi_agent` feature: Sol has `spawn_agent`, `wait_agent`, `send_message`, `followup_task`, `interrupt_agent`, `list_agents`; sub-agents can spawn their own (capped by `agents.max_depth` / `agents.max_threads`). Live under the pinned exec invocation — `--ignore-user-config` does not disable it. Children INHERIT the session sandbox (verified: a child of a workspace-write parent wrote inside the workspace and got `Read-only file system` outside it; host-checked both ways).

- **Use for read-heavy intra-lot parallelism**: bulk exploration, per-module surveys, multi-lens review inside ONE delegation. When a lot is embarrassingly parallel, say so in the prompt ("fan out sub-agents over the per-module survey; merge their findings") — flat-rate, self-coordinating, one result to read.
- **Not for parallel implementation**: sub-agents share one working tree with zero isolation — codex's own worker prompt just tells them not to revert each other's edits. Parallel write lots stay orchestrator-side: separate `codex exec` runs in separate `git worktree`s, merged after review.
- Review math unchanged: however many agents Sol spawns internally, it is one session and one diff — the full review gate applies to the whole output.
- `spawn_agents_on_csv` (CSV batch harness: one worker per row, `{column}` templates, per-worker output schema, 16-way concurrency) exists in the binary but is gated behind `enable_fanout` (under development, off) — re-check on codex upgrades.
- Fan-out burns the flat-rate usage window faster; keep it purposeful, not decorative.

## Fleet lane (parallel implementation lots — verified 2026-07-14)

Trigger on an implementation task that decomposes into >=2 file-disjoint lots. Decomposition is orchestrator design work: partition by file ownership; if two lots would touch the same file, merge them into one lot or serialize them. Disjointness is what makes merges trivial.

Each lot gets its own frozen spec, `$RUN` dir, and session id. Decide network at dispatch per lot (see sandbox tiers).

Mechanics, verified 2026-07-14 with two parallel live runs: correct edits per worktree, zero cross-contamination.

```bash
FLEET="$(mktemp -d "$HOME/.cache/fleet.XXXXXX")"   # NOT $XDG_RUNTIME_DIR: tmpfs — a reboot eats un-merged lot diffs, and it's too small for dep-heavy repos
git -C <repo> worktree add "$FLEET/lot1" -b fleet/lot1
git -C <repo> worktree add "$FLEET/lot2" -b fleet/lot2
# one standard headless invocation per lot (own $RUN dir), backgrounded, -C "$FLEET/lotN"
```

- `git status` / `git diff` work inside a sandboxed worktree even though the shared `.git` lives outside the workspace root: the sandbox confines writes, not reads, and Sol never commits (standing guardrail), so no `.git` writes are needed. Verified 2026-07-14.
- Concurrency cap: 4–6 lots in flight. Flat-rate still has a finite ChatGPT usage window; queue the rest.
- Mid-fleet degradation: a hard-unavailability signal on any lot (see "When Sol is unavailable") switches the remaining undispatched lots to Claude subagents (`Agent`, isolation: `"worktree"`, model per the fallback ladder). In-flight lots run to completion.
- Review + merge are orchestrator-side and sequential: full-diff review + proof run per lot in its worktree; a lot branch has NO commits until review passes (Sol never commits), so the orchestrator commits each reviewed lot on its `fleet/*` branch itself, then merges lot branches one at a time into an integration branch; run the whole-suite integration proof after the last merge. File-disjointness keeps conflicts near zero. For ship-gating, the verify panel runs on the **integrated diff**, not per lot.
- Fleet width is bounded by the orchestrator's review bandwidth, not Sol's throughput. Every merged diff still gets a full read; keep lots small enough to genuinely review.
- Cleanup after merge: `git worktree remove "$FLEET/lotN"` (`--force` for an abandoned dirty lot), then delete the `fleet/*` branches. Worktrees live outside the repo, so no `.gitignore` churn.
- Sol-side fan-out covers read-heavy parallelism **inside one lot**; the fleet lane is its write-side complement **across lots**.

## Follow-ups (resume — cheaper than fresh runs, keeps Sol's context)

Use the `$SID` captured from the first run's `thread.started` event (above); with parallel runs never trust `--last`. Resume writes into a fresh `$RUN` dir too:

```bash
(cd <repo> && codex exec resume "$SID" --ignore-user-config \
  --json -o "$RUN2/result.md" - <"$RUN2/prompt" >"$RUN2/events.jsonl" 2>"$RUN2/err")
```

`resume` has no `-C`: run from the repo dir. It inherits the original run's sandbox (verified). Outside a git repo it needs `--skip-git-repo-check`. If resume exits nonzero (session gc'd / `CODEX_HOME` changed / state cleaned): do NOT `--last` — start a fresh pinned session re-supplying the frozen spec, current diff, and prior findings.

## Prompt contract

Sol starts with zero session context. Every prompt: goal, exact repo/paths, constraints, non-goals, proof expected (exact test command), output shape ("report files changed + test output + risks"). Spec quality decides success. `~/.codex/AGENTS.md` carries the standing guardrails (no commits, no secrets, no prod) — don't restate them, but don't rely on them replacing a scoped prompt either.

## Verify (Fable, always)

- `git status -sb` + read the full diff; judge like a contributor PR
- run focused tests yourself or demand proof output; Sol claims are advisory. Caveat: running Sol-touched tests on the host is an execution trampoline — a delegate can hide a payload in `package.json`/a test runner/a fixture that fires when Fable runs `npm test` outside the sandbox. On untrusted code, diff the test/build entrypoints against base before running, or run verification in the sandbox too.
- iterate via resume; after 2 failed rounds, take over and do it directly
- Fable commits; normal closeout (review, verify) still applies

## Economics

Win = generation + exploration tokens moved to Sol; Fable spends only on spec + diff review. Don't ping-pong trivia through delegation; don't re-read what Sol already summarized.
