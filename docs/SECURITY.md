# Security model

This system was adversarially reviewed by Sol (its own delegate) through the review lane on 2026-07-14; Fable arbitrated. This doc records the resulting threat model honestly rather than overselling the guardrails.

## Threat model / intended use

Designed for a **single trusted user delegating work on repos they author or trust** (own projects, own dependencies). Within that boundary the sandbox tiers and guardrails are appropriate.

**Do NOT, without extra isolation, point Sol at untrusted third-party code** (a repo you're reviewing for someone else, an unvetted dependency tree, attacker-supplied fixtures). Two reasons:

1. **Read boundary is not confined.** `workspace-write` and `read-only` confine *writes*, not *reads*. A delegate reading an untrusted repo can read anything the invoking user can — `~/.ssh`, cloud config, tokens — and codex auto-loads that repo's own `AGENTS.md` after the global one (closer instructions win), so a malicious repo can *instruct* the delegate to do so. Even with shell networking off, tool output returns to the model service and can be written into files Fable later consumes.
2. **Verification is an execution trampoline.** "Fable runs the tests itself" runs Sol-touched `package.json` / test-runner / fixtures *outside* the sandbox with Fable's full credentials. Reading the diff first is model review, not containment.

For untrusted code: use `--ignore-user-config` (already the default here), run under a credential-free HOME/UID, keep network off, diff test/build entrypoints against base before executing, and treat the whole run as hostile output.

## Enforcement matrix — what actually stops what

| Control | Mechanism | Enforced by | Bypassable when |
|---|---|---|---|
| Writes confined to workspace+tmp | codex `workspace-write` sandbox | OS (landlock/bwrap) | — (writes only; reads unrestricted) |
| No writes at all (reviews) | codex `read-only` sandbox | OS | — |
| Spawned-command network off | `network_access=false` (default) | OS | you set `network_access=true` (then egress is direct/unproxied) |
| `-o` result file can't clobber user files | unique `mktemp -d` dir outside sandbox roots | convention in skill | reverts if someone hardcodes `/tmp/codex-*.md` (that's the verified symlink escape) |
| No config.toml MCP/roots/network-defaults leak in | `--ignore-user-config` | codex flag | omitting it; and it does NOT cover a standalone `~/.codex/hooks.json`, which still loads |
| No commit / push / prod / secrets | `~/.codex/AGENTS.md` + scoped prompts | **model instruction only** (advisory) | prompt injection via repo AGENTS.md; network/MCP tools enabled |
| Sol output never auto-applied | Fable reads diff + runs tests | Fable (the human-in-loop model) | test-trampoline payloads (see above) |

Hook caveat: `--ignore-user-config` ignores `config.toml` only; a standalone `~/.codex/hooks.json` still runs (outside the shell sandbox) and could export prompts/repo content. Keep that file empty/absent, or accept it under the single-user trusted boundary. The Herdr visible mode launches plain interactive `codex`, which loads the full ambient surface by design.

The bottom two rows are the soft boundary. They hold for trusted repos; they are the first thing an untrusted repo attacks.

## AppArmor bwrap profile — honest blast radius

`system/apparmor/bwrap` grants `userns` to `/usr/bin/bwrap` with `flags=(unconfined)`. This is **not codex-scoped** — on this machine `/usr/bin/bwrap` is world-executable, so *any* local process can now use bwrap to create user namespaces, re-opening the unprivileged-userns kernel attack surface Ubuntu 24.04 restricts by default. It does not grant host root. Accepted trade-off on a single-user workstation; on a shared/multi-user box, prefer a group-constrained launcher or upstream's `bwrap-userns-restrict` profile instead.

Also: codex ships a bundled `codex-resources/bwrap` and a native landlock/seccomp path; the profile only matches `/usr/bin/bwrap`. Install the system `bubblewrap` package and verify the resolved binary is `/usr/bin/bwrap` (README install steps), or a fresh box may silently use an unprofiled sandbox path.

## Reporting

Single-maintainer project. No formal disclosure process — open a GitHub issue for security concerns. This is a personal orchestration setup, hardened for a trusted single-user workflow (see threat model above), not a multi-tenant product.
