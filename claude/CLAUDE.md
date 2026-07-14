# Routing: Fable ↔ Sol orchestration

- Implementation-shaped work (build from a frozen spec, refactor, mechanical migration, bug fix with known repro, test writing, bulk exploration): use `$codex-first` — delegate to Codex CLI (Sol), then review its output yourself.
- Design, architecture, UX judgment, tiny edits (<~20 lines), MCP/secret-dependent work, prod ops, and all git commits/pushes: stay in Claude; do not delegate.
- Inside Herdr (`HERDR_ENV=1`) with the user watching: prefer the visible herdr transport described in `$codex-first`.
