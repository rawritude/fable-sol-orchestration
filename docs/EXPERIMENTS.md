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

## Open experiment queue

- E2: luna vs sol as implementer at high, full exec loop, Sol reviewing both.
- E3: does the plan-review lane (Sol reviewing Fable's spec pre-implementation) measurably reduce fix rounds?
