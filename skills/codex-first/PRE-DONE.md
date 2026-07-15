# Pre-done checklist (implementation lots)

Appended to every implementation-lot prompt. Run ALL items before declaring the lot done. Every item traces to a real defect that shipped in a green, self-reviewed PR and was only caught at a later ship-gate review — these are the specific blind spots author-side self-review does not catch on its own. Goal: the lot catches its own cheap 75% so the review gate spends its attention on the genuinely hard cross-system 25%.

Each item states the principle, not just the rule — apply it to novel cases, don't pattern-match the example.

**a. Live-flow proof — test through the real flow, not around the seam you changed.**
If you changed anything a writer snapshots (e.g. an adapter read whose output feeds a fold/append stage, or any state a later stage reads back), the failing/passing test MUST exercise the real writer/engine flow. Do not insert rows directly and read them back — that proves the query works, not that the fix works. *Principle: a seam-local test of a seam-crossing change proves nothing.* Came from: a readback that passed its own insert-and-read test but suppressed live-path journaling (the engine wrote the delivery row before journaling in the same tx, so the readback pre-seeded head-state → fold dedup → the event never journaled → permanent replay divergence). The test never ran the live path, so it was invisible.

**b. Deferral comments are rulings — don't delete them to make room.**
A code comment saying "deliberately not done yet / wired at wave X / [] on both sides so the invariant holds trivially" is a recorded design constraint, often a prior owner ruling. Never delete one without addressing its stated reason in your report. If the reason still holds, your fix is probably wrong. *Principle: a documented deferral is a mini-ruling; overwriting it silently discards a decision you may not have the context to reverse.*

**c. Closure — enumerate the other side of every contract you touch.**
For every column/field your new logic reads, grep its writers (and vice versa). A read with no production writer is a dead invariant that will evaluate to a constant forever. Separately: treat the issue body's evidence/affected-lines list as an acceptance checklist — every instance it cites is either fixed or explicitly declared out-of-scope with a reason in your report. *Principle: a fix that only touches one side of a read/write contract, or one of several cited instances, is a partial fix wearing a "closes #N" label.* Came from: (1) new logic that read a `*_expires_at` column no rule path ever wrote → every rule-classified item stuck pending forever; a 30-second grep for the writers would have shown it. (2) A PR that closed an issue while leaving the issue's explicitly named second instance (a sibling pipeline) unfixed.

**d. Widening audit — ask what your change newly permits.**
If the fix widens any environment — a search_path/pin, a GRANT, a relaxed check, a broadened catch — write one paragraph in your report: what does this newly permit that was previously impossible? And never write doc/RULINGS/comment text claiming stronger enforcement than the code actually enforces. *Principle: widening a boundary to fix one case silently legalizes every other case on the far side of that boundary.* Came from: pinning `search_path=public` to fix frozen-ledger replay also let every future migration use unqualified public symbols — and the accompanying doc text claimed comprehensive protection a 2-symbol regex gate didn't provide.

**e. No-op + concurrency — test the vacuous path and the two-client path.**
Test the path where your code does nothing (empty queue, zero rows, already-satisfied condition): can a vacuous pass masquerade as success (e.g. a health signal recovering after an operation that performed no I/O)? And any exactly-one-wins / latest-wins invariant requires a two-client concurrency argument or test — whether or not the issue mentions races. *Principle: "it didn't throw" is not "it worked," and an invariant asserted only under serial execution is not an invariant.* Came from: (1) pump health called recordSuccess after an empty-queue no-op → /health went green without proving recovery. (2) A "latest approval wins" supersession fix that two concurrent ratifications both bypassed (each saw the other as still-pending), leaving both active — shipped with no concurrency test.

**f. Runtime role — SQL is checked against the executing role's real grants.**
SQL added on a runtime path must be validated against the executing role's actual grants (see the repo's migration/grant files), not the DB owner. Row-lock clauses (FOR UPDATE / FOR SHARE / FOR KEY SHARE / FOR NO KEY UPDATE) require UPDATE privilege. Owner-run integration tests run as superuser and structurally mask privilege errors. When you cannot run the test as the real role in-sandbox, name this risk explicitly in your report. *Principle: a test that runs as a more-privileged role than production is testing a different program.* Came from: a FOR KEY SHARE replay lock that passed the owner-run integration test but throws permission denied at runtime as the writer role (which deliberately lacks UPDATE on that table).

**g. End-of-lot main re-sync — composition with current main is part of done.**
Before writing your report, `git diff origin/main` against your base for the subsystems you touched, and state whether anything that landed mid-lot interacts with your fix — a newly-typed field, a new health/observability surface, a claimed migration slot, a renamed export. Re-verifying the issue at lot start is not enough; main moves during the lot. If your sandbox has no network, diff against the `origin/main` ref visible in your worktree and NAME its staleness in the report — the orchestrator re-checks against live main at merge, but your job is to declare which subsystems that check must cover. *Principle: "correct against the base I branched from" ≠ "mergeable and coherent against the main that exists now."* Came from: two lots whose fixes were correct at branch time but stale against a mid-lot main commit they then had to integrate with; also a migration that claimed a slot main had already claimed.

**h. Sibling files — request stacking, never recreate.**
If the seam/helper/contract your fix needs exists only in another in-flight lot's branch, STOP and request to be stacked on that lot (end your report with the request; do not write the file). Recreating a sibling lot's file — even byte-for-byte identical — IS a file collision and will diverge at merge. *Principle: two lots authoring "the same" file are not disjoint; they are a guaranteed merge conflict wearing a disguise.*

## Report addition

End the lot report with a "Pre-done checklist" section: one line per item a–h, each either `PASS — <how proven>` or `N/A — <why this lot doesn't touch it>`. An item that is neither is an incomplete lot. This makes the reviewer's job "confirm the claims" instead of "rediscover the gaps."

## Economics

At ship-gate, each missed item costs a full panel → verify → fix → re-verify round-trip. Each checklist item is a sub-minute check at authoring time. Eight such misses across ~19 PRs is the difference between a review gate that confirms clean work and one that re-does it. If lots run this honestly, the gate scales; if they don't, the orchestrator absorbs the cost.
