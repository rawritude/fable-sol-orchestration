# Pilot: oracle-gated funnel vs. bare fleet lane

A/B test of the fan-out playbook's "funnel" architecture against the current fleet lane, on the same greenfield task. Measures the scarce resource (Fable review burden), wall-clock, and escaped defects. n=1 demonstration + rough measurement, not a powered result.

## Task (identical for both arms)

Build `jobkit`, a stdlib-only Python toolkit, three file-disjoint modules from frozen specs (`~/.cache/pilot/specs/`): `ratelimit.py` (sliding-window limiter), `retry.py` (backoff delays + retry runner), `dedupe.py` (TTL idempotency store). Each has real edge surface — window boundary, `factor**i` overflow, TTL expiry edge, record-only-accepted — where Sol at `high` plausibly errs.

## Arm A — control (current fleet lane)

1. Dispatch 3 parallel Sol `high` lots, one per module (workspace-write, isolated dirs).
2. Fable reviews **every** diff. Review burden = total impl lines Fable must read (all 3 modules, in full).
3. Merge.

## Arm B — funnel

- **Stage 0 (oracle):** Sol writes a pytest oracle per module from the frozen spec (parallel). The oracle is the objective definition of done. Fable reviews the *oracle* (tests are cheaper to vet than impls) — its cost is amortized across every lot the oracle gates.
- **Stage 1 (implement):** 3 parallel Sol `high` lots, same as Arm A.
- **Stage 3a (automatic gate):** run each impl against its frozen oracle. Pass → proceeds; fail → bounce + resume (counted).
- **Stage 3b (cheap review):** a Sol read-only reviewer distills risk-ranked findings per module.
- **Stage 3c (Fable, rationed):** Fable reads the distilled findings + oracle results, and raw diff **only** where a reviewer flags risk. Review burden = distilled lines + flagged raw sections only.

## Metrics

- **Wall-clock** end to end (funnel has extra automated stages; expected to trade some wall for the two below).
- **Fable review burden** = lines Fable must actually read. The scarce resource; the headline metric.
- **Escaped defects** = real defects surviving each arm's process, measured by a held-out audit run identically on both final artifacts: an independent `ultra` Sol audit (E7: best at execution-checkable defects) + a hidden property-test battery authored by Fable. Lower is better.

## Honest expectation

Funnel trades a modest wall increase (Stage 0 + 3b are extra) for a large Fable-burden reduction and equal-or-fewer escaped defects. It wins when Fable's serial review is the real bottleneck (the multi-lot real-world case), not necessarily on a 3-lot toy. The pilot's job is to size those trades, not to prove a foregone conclusion — a null result (both arms clean, funnel only saved burden) is a legitimate outcome.

## Doctrine change under test

The funnel modifies D6 (Fable reads every diff) to "Fable reads every diff that survived the oracle + cheap-review filter, plus random spot-audits of the filtered-out set to keep the filter honest." A false-PASS from a cheap reviewer or a weak oracle is the new failure mode; spot-audits are the mitigation.

## Results (run 2026-07-17, n=1)

Generation held constant: Arm B's funnel processed the *same* 3 Sol-`high` impls Arm A produced (234 impl lines: 65+112+57), so the only variable is the review architecture. Oracle: 81 tests / 795 lines across 3 modules.

**Oracle gate (Stage 3a) fired 21 failures — adjudicated by Fable:**
- **1 real defect:** `ratelimit` float-precision boundary — at a sub-normal negative `now`, `now - window` loses precision and equals the record's timestamp exactly, pruning a record still inside the window (`allow` returns True where spec says False). Same defect *class* ultra caught in E7; execution surfaced it for free.
- **20 false positives:** unmandated `now`/key type+finiteness validation (dedupe, 16) and literal-`True` pedantry on the spec's ambiguous "is True" wording (retry, 3) and a huge-int overflow (ratelimit, 1). Every FP traces to **spec ambiguity or unstated validation** — not impl error.

**Bare-fleet `high` review (Arm A's actual review path) — run for comparison:** caught **2 different real defects** the oracle never tested — the out-of-order-timestamp pruning assumption and a subnormal `compute_delays` discrepancy (repeated-multiply vs `base*factor**i`) — with **0 false positives**. It **missed** the float-precision boundary the oracle caught.

**Metrics.**

| | Arm A (bare fleet) | Arm B (funnel) |
|---|---|---|
| wall-clock | 54s | 178s+ (oracle-gen dominated) |
| Fable must read | 234 impl lines | 795 oracle lines (vet for over-reach) + 21 adjudications + flagged impl |
| real defects caught | 2 (missed float-precision) | 1 via oracle (missed the 2 review found) |
| false positives to filter | 0 | 20 |

## What the pilot actually taught (it refined the architecture, didn't rubber-stamp it)

1. **Oracle and reasoning-review are COMPLEMENTARY lenses, not substitutes.** Execution-gating (oracle) catches arithmetic/boundary collapses; reasoning-review catches semantic assumptions (ordering) and cross-expression discrepancies. Union of both = 3 distinct real defects; either alone = 1 or 2. The funnel must **layer** them, not replace review with the oracle.
2. **A Sol-authored oracle over-reaches — Stage 0 vetting is MANDATORY, not optional.** 20/21 failures here were the oracle inventing requirements. Blindly trusting "oracle red = bounce" would send spec-correct code back for pointless fixes. Fable must tighten the oracle against the spec before it gates.
3. **Over-reach traces straight to spec ambiguity.** "is True" and unstated validation caused every FP. Tighter spec → tighter oracle → fewer FPs. This is "fan out the work, not the ambiguity" (fan-out playbook) proven from the other direction: ambiguity doesn't just diverge implementations, it diverges *oracles*.
4. **The toy can't show the burden win.** Tiny impls + a thorough oracle invert the ratio (795 oracle lines > 234 impl lines). The Fable-burden reduction is a *large-impl, amortized-oracle* claim; a 3-module toy is the wrong scale to demonstrate it. What the toy *does* demonstrate is the defect-catching complementarity and the oracle-over-reach risk — both real and both generalizing.

## Revised funnel doctrine (supersedes the naive version)

- Stage 0 produces the oracle AND Fable tightens it against the spec (strip invented requirements) — the oracle-vetting cost is the price of the automatic gate; front-loaded and amortized across every lot and iteration it gates.
- The oracle is an ADDITIONAL execution lens layered under reasoning review, not a replacement for D6. Oracle-red is a *signal to adjudicate*, not an auto-bounce.
- For the execution-checkable defect class specifically (float precision, boundary collapse, overflow), the oracle and an `ultra` arm are the two tools that find it; reasoning review at any effort tends to miss it (E6/E7 + this pilot agree).
- Escaped-defect reduction comes from the UNION of lenses (oracle + reasoning review + optional ultra), which is the real argument for spending surplus usage on width: more independent lenses, each catching a class the others miss.
