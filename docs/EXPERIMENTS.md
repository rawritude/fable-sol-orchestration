# Experiments

## E1 — gpt-5.6-sol effort: high vs xhigh (2026-07-14)

**Setup.** One frozen spec: async LRU+TTL+stale-while-revalidate+singleflight cache in TypeScript — 7 normative semantics with deliberately nasty interleavings (expired get reusing an in-flight background refresh, delete-during-flight, expired-preferred eviction, background-refresh-lands-as-MRU). Identical prompts, no-exec generation mode (files emitted as text; isolates pure generation quality from tool-loop noise), fast_mode on for both, only `model_reasoning_effort` varied. Judged by a 14-test adversarial bun suite written blind from the spec by the orchestrator, plus cross-running each model's own tests against the other's implementation.

**Results.**

| | high | xhigh |
|---|---|---|
| wall clock | 222 s | 385 s (+73%) |
| tokens | 14,832 | 22,983 (+55%) |
| own tests | 13/13 | 12/12 |
| blind judge suite | **14/14** | **14/14** |
| cross-suite | pass | pass |

Both produced the same architecture (Map-as-LRU via delete/re-insert, flight object with store-allowed flag, lazy clock-based expiry) and near-identical RISKS notes.

**Conclusion.** `high` is the delegation default; xhigh is an escalation lever after a failed verify round, not a preemptive setting.

**Caveats.** n=1 task, one domain (async TS), generation-only mode. Worth re-running with the full exec loop (sandbox now works), and worth adding a `gpt-5.6-luna`-as-implementer arm.

## E4 — review-lane recall: high vs xhigh (2026-07-15)

**Setup.** Instrument: a 345-line correct async task-scheduler module (base) plus a candidate revision seeding 10 precisely-specified bugs — 3 easy (retry off-by-one, silently-swallowed persistence exception, inverted priority ordering), 4 medium (always-true TTL comparison, lost `return_exceptions=True`, semaphore released only on the happy path, removed filename sanitization → path traversal), 3 hard (check-then-act spanning an `await` suspension point, mutable default argument shared across instances, `return` inside `finally`) — plus 6 benign distractor changes. Sol generated the instrument from a frozen bug spec in a separate session; the orchestrator independently verified every seeded bug against the diff before any review ran. Reviewers saw only a scratch git repo with base+candidate commits — the manifest never existed inside the repo. Three fresh-session runs per effort level through the standard read-only review lane (identical SHA-pinned prompts, anti-noise contract, `--ignore-user-config`); only `model_reasoning_effort` varied.

**Results.** (one xhigh run died transiently mid-stream — empty stderr, truncated event log, no usage signal; retried once per doctrine and the retry is what's counted)

| | high (n=3) | xhigh (n=3) |
|---|---|---|
| recall (of 10) | 9, **10**, 9 — mean **9.33** | 9, 9, 9 — mean 9.00 |
| false positives | 0 | 0 |
| wall clock | 135–174 s (mean 158) | 157–329 s (mean 220, +39%) |
| output tokens | mean 4,470 | mean 7,732 (+73%) |
| transient failures | 0/3 | 1/4 |

Per-bug: all six runs caught the same 9 of 10 — including two of the three hard bugs. The sole discriminator was H1 (cache check-then-act spanning a suspension point): caught exactly once, by a **high** run. Both efforts also flagged real unseeded blast-radius consequences of the mutable-default edit (API regression for tuple/`None` hook args) — counted with that bug, not as FPs.

**Conclusion.** The "review is search, so search rewards depth" hypothesis is refuted at this difficulty: xhigh bought +73% output tokens and +39% wall for slightly *worse* mean recall. Review lanes pin `high`, same as generation; xhigh stays an escalation lever only. The bug class neither effort reliably catches (races across suspension points) is a **width** problem — a dedicated concurrency lens in the verify panel, additional independent rounds — not a depth problem.

**Caveats.** n=3 per arm, one instrument, and a ceiling effect: 9/10 was universal, so a single bug carried all the discriminating power. A harder instrument (subtler tiers, larger diff) could still separate the efforts. The instrument is kept outside this repo; regenerate a fresh one for future benchmarks — a published instrument is eventually burned.

## Open experiment queue

- E2: luna vs sol as implementer at high, full exec loop, Sol reviewing both.
- E3: does the plan-review lane (Sol reviewing Fable's spec pre-implementation) measurably reduce fix rounds?
- E5: does a dedicated concurrency-lens reviewer reliably catch suspension-point races (E4's H1 class) that generalist reviewers miss at every effort?
