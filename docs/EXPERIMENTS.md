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

## E6 — judgment-heavy comparative audit: high vs xhigh (2026-07-15)

**Setup.** Tests the one role E1/E4 didn't: judgment, not generation or bug-recall. Instrument: four candidate `SlidingWindowRateLimiter` implementations of one spec — A correct+clean (intended best), B correct+over-engineered (taste #2), C a planted off-by-one (`len <= cap` admits one extra, D1), D a planted fixed-window spec-misread (2× boundary burst, D2). Sol generated it; the orchestrator behaviorally verified ground truth before any audit ran (A/B admit 3, C admits 4, D admits 6 in a boundary-burst harness — not just read the manifest). Audit task: diagnose defects, rank all four, recommend one. Three fresh-session runs per effort through the read-only lane, identical prompts, effort the only variable. Two metrics: objective (planted-defect catch + clean recommendation) and a **blind quality panel** — 3 fresh judges rank the 6 anonymized audits (arms shuffled, not grouped) on defect precision, justification honesty, decisiveness, and depth beyond the obvious.

**Results.**

| | high (n=3) | xhigh (n=3) |
|---|---|---|
| D1 + D2 caught | 3/3 both | 3/3 both |
| ranking / recommendation | `a,b,c,d` / A — all 3 | `a,b,c,d` / A — all 3 |
| **mean blind rank** (1=best…6=worst) | **3.33** | 3.67 |
| best / worst single artifact | 1.67 / 5.00 | **1.33** / **6.00** |
| top-3 finishes (of 9 slots) | 5 | 4 |
| wall / output tokens | 105s / 5.0k | 122s (+16%) / 6.2k (+24%) |

**Conclusion.** Refuted. Every objective metric tied at ceiling (all six caught both planted defects with correct line + operator + failure mode, all ranked identically). On blind quality the arms are a statistical wash (3.33 vs 3.67, n=3), and the *shape* is the finding: **xhigh produced both the single best artifact AND the unanimous worst** — higher variance, not higher level. The field's "best artifact of the day was the one xhigh run" (n=1) is exactly consistent with that variance, not evidence of a level shift. The real quality discriminator wasn't either planted defect (everyone caught those) but an *unseeded* subtlety — the deque pruning assumes non-decreasing timestamps, which the spec never guarantees; the top artifacts connected it to production reality, the worst waved at it — and catching-it-deeply did **not** track effort. So `high` is the default for judgment too; the way to buy judgment quality with surplus usage is **best-of-N + a blind panel** (which samples exactly the per-run variance xhigh exhibits), not preemptive effort. This completes the sweep: depth doesn't beat width in any of the three measured Sol roles (generation E1, review E4, judgment E6).

**Caveats.** n=3/arm, one instrument, ceiling on every objective axis (so the panel carried all discrimination), and the judge panel is itself Sol-at-high — a judge with its own blind spots. A harder instrument (closer A-vs-B, subtler planted defects) could still separate the arms.

## E7 — ultra effort: does auto-delegation + tool-loop beat high? (2026-07-17)

**What ultra is.** `gpt-5.6-sol` has a 6th effort level above `max`: `ultra` — catalog description "Maximum reasoning with automatic task delegation." The model spawns and coordinates its own sub-agents (`multi_agent`, stable/default-on) and drives its tool loop harder. Distinct from xhigh (E6): not just more thinking, but self-delegation + empirical exercise of the artifact.

**Setup.** Same E6 instrument (4 rate-limiter candidates, 2 verified planted defects), same audit prompt. 3 fresh `ultra` runs, blind-paneled (3 fresh judges, arms shuffled) against the 3 E6 `high` artifacts.

**Results.**

| | high (E6) | ultra |
|---|---|---|
| D1+D2 caught / ranking | 3/3, all `a,b,c,d`/A | 3/3, all `a,b,c,d`/A |
| **mean blind rank** (1=best…6=worst) | 3.78 | **3.22** |
| best / worst single artifact | 2.00 / 6.00 | **1.00** / 5.00 |
| sub-agent spawns per run | 0 | 0–4 |
| command executions per run | 0 (reasoned about code) | **12–14 (exercised code)** |
| wall / output tokens | 105s / 5.0k | 240–338s (~2.7×) / 6.7–12.6k (~2×) |

**Conclusion.** Ultra earns a real but bounded role. Its mean edge over high is modest and within n=3 noise (3.22 vs 3.78), and its variance is just as high — it produced the unanimous #1 AND a middling #5. But the *mechanism* is a genuine difference E6's efforts don't have: ultra runs its tool loop to **empirically exercise the code** (12–14 command executions every run — threaded concurrency probes, float-precision checks, boundary tests) instead of reasoning about it. The panel-winning ultra artifact caught real defects (float-cutoff collapse `1e20 - 1.0 == 1e20`, concurrency-induced timestamp reordering) that **no high or xhigh run in E6 found** — the judge cited exactly that depth. This is D6 (evidence over claims) executed by Sol itself.

So: ultra is an **accuracy lever for ship-gate-critical / hard-correctness lots**, best used *inside best-of-N* (its variance means a single ultra run isn't reliable dominance; the batch-best is what wins). It is NOT faster — 2–3× wall on a bounded prompt, up to 5× on an open-ended one — so it does nothing for throughput. Cost 2–3× tokens. Not a blanket default; a targeted spend when correctness matters more than latency and usage is abundant.

**Caveats.** n=3, one instrument, ceiling on objective metrics (panel carried discrimination), self-judged by Sol-at-high. Ultra's empirical-verification edge should show larger on tasks where claims are checkable by execution (this one was); it may add less on pure design/taste work.

## Open experiment queue

- E2: luna vs sol as implementer at high, full exec loop, Sol reviewing both.
- E3: does the plan-review lane (Sol reviewing Fable's spec pre-implementation) measurably reduce fix rounds?
- E5: does a dedicated concurrency-lens reviewer reliably catch suspension-point races (E4's H1 class) that generalist reviewers miss at every effort?
- ~~E6~~ DONE (above): xhigh does not reliably beat high on judgment either — higher variance, tied mean. Width (best-of-N + panel) is the lever.
