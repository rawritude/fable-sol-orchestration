#!/usr/bin/env bash
# Installer for the Fable<->Sol orchestration files.
#
# Non-interactive and non-destructive by default:
#   ./install.sh          preflight + dry-run (prints what it WOULD do, writes nothing)
#   ./install.sh --apply   actually install
#   ./install.sh --apply --force   overwrite differing skill files without prompting
#
# Skills are whole files (we own them). CLAUDE.md / AGENTS.md are updated inside a
# delimited MANAGED BLOCK so your other content in those files is preserved.
# Every mutation is preceded by a timestamped .bak.

set -euo pipefail
cd "$(dirname "$0")"
REPO="$(pwd)"

APPLY=0; FORCE=0
for a in "$@"; do case "$a" in
    --apply) APPLY=1 ;;
    --force) FORCE=1 ;;
    *) echo "unknown arg: $a" >&2; exit 64 ;;
esac; done

say() { printf '%s\n' "$*"; }
would() { [ "$APPLY" = 1 ] && return 1 || return 0; }

# ---- preflight (never mutates) --------------------------------------------
fail=0
command -v codex >/dev/null || { say "MISSING: codex not on PATH"; fail=1; }
command -v jq    >/dev/null || { say "MISSING: jq (session-id capture needs it)"; fail=1; }
if command -v codex >/dev/null; then
    ver="$(codex --version 2>/dev/null || true)"
    say "codex: $ver"
    case "$ver" in *0.14[4-9]*|*0.1[5-9]*|*0.[2-9]*) : ;;
        *) say "WARN: pinned flags validated against 0.144.x; verify --ignore-user-config / --json on $ver" ;;
    esac
fi
if command -v bwrap >/dev/null; then
    bp="$(command -v bwrap)"; [ "$bp" = /usr/bin/bwrap ] || say "WARN: bwrap resolves to $bp, not /usr/bin/bwrap — AppArmor profile only matches the latter"
else
    say "WARN: system bubblewrap not installed — 'sudo apt install bubblewrap' before relying on the sandbox"
fi
[ "$fail" = 0 ] || { say "preflight failed; fix the above and re-run"; exit 1; }

# ---- whole-file installs (skills) -----------------------------------------
install_file() {
    local src="$1" dst="$2"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then say "ok (unchanged): $dst"; return; fi
    if [ -f "$dst" ] && [ "$FORCE" = 0 ]; then
        say "DIFFERS: $dst (use --force to overwrite; diff below)"; diff -u "$dst" "$src" || true
        [ "$APPLY" = 1 ] && { say "  skipped (no --force)"; return; }
    fi
    if would; then say "would install: $dst"; return; fi
    mkdir -p "$(dirname "$dst")"
    [ -f "$dst" ] && cp "$dst" "$dst.bak.$(date +%s)"
    cp "$src" "$dst"; say "installed: $dst"
}
install_file "$REPO/skills/codex-first/SKILL.md"    "$HOME/.claude/skills/codex-first/SKILL.md"
install_file "$REPO/skills/codex-first/PRE-DONE.md" "$HOME/.claude/skills/codex-first/PRE-DONE.md"
install_file "$REPO/skills/herdr/SKILL.md"          "$HOME/.claude/skills/herdr/SKILL.md"

install_file "$REPO/bin/sol-run" "$HOME/.local/bin/sol-run"
if [ "$APPLY" = 1 ] && [ -f "$HOME/.local/bin/sol-run" ]; then chmod +x "$HOME/.local/bin/sol-run"; fi
case ":$PATH:" in *":$HOME/.local/bin:"*) : ;; *) say "WARN: ~/.local/bin not on PATH — sol-run won't resolve" ;; esac

# ---- managed-block merge (instruction files) ------------------------------
# Replaces content between markers, leaving the rest of the user's file intact.
merge_block() {
    local src="$1" dst="$2" tag="$3"
    local begin="# >>> fable-sol:$tag >>>" end="# <<< fable-sol:$tag <<<"
    local body; body="$(cat "$src")"
    local new; new="$(printf '%s\n%s\n%s\n' "$begin" "$body" "$end")"
    if [ -f "$dst" ] && grep -qF "$begin" "$dst"; then
        if would; then say "would update managed block in: $dst"; return; fi
        cp "$dst" "$dst.bak.$(date +%s)"
        awk -v b="$begin" -v e="$end" -v repl="$new" '
            $0==b {print repl; skip=1; next} $0==e {skip=0; next} !skip {print}
        ' "$dst" > "$dst.tmp" && mv "$dst.tmp" "$dst"
        say "updated managed block: $dst"
    else
        if would; then say "would append managed block to: $dst"; return; fi
        mkdir -p "$(dirname "$dst")"
        [ -f "$dst" ] && cp "$dst" "$dst.bak.$(date +%s)"
        { [ -f "$dst" ] && printf '\n'; printf '%s\n' "$new"; } >> "$dst"
        say "appended managed block: $dst"
    fi
}
merge_block "$REPO/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" routing
merge_block "$REPO/codex/AGENTS.md"  "$HOME/.codex/AGENTS.md"  guardrails

would && say $'\nDry run. Re-run with --apply to write.'
say $'\nAppArmor (sudo, once) — see README "Install" for the validated 4-line block.'
