#!/usr/bin/env bash
# webapp-security-orchestrator installer.
# Installs the claude-red skills (sparse) and renders the orchestration agents into the
# live config dirs for the pi and/or Claude Code harness. See README.md.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED_URL="https://github.com/SnailSploit/claude-red"

# --- defaults ---------------------------------------------------------------
CMD="install"
HARNESS=""
RED_DIR="$HOME/claude-red"
OUT_DIR="$REPO_DIR/out"
DRY_RUN=0
DO_TEST=0

# claude-red skill domains this pipeline installs and resolves. Each class folder is always
# offensive-<class>. Add a domain to this one list and it is sparse-cloned + smoke-tested
# automatically; new offensive-* skills inside an already-cloned domain are picked up with no
# edit here (both the agents and the smoke test discover skills by globbing these dirs rather
# than a hardcoded class list, so claude-red adding skills does not require a change).
DOMAINS="web auth api crypto"

usage() {
  cat <<USAGE
Usage: setup.sh [install] [--harness pi|claude|both] [--red-dir DIR] [--out-dir DIR] [--dry-run] [--test]
       setup.sh test

  install (default)   install skills + render agents for the chosen harness(es)
  test                run the non-destructive smoke test only (no install)

  --harness VALUE     pi | claude | both   (prompted if omitted)
  --red-dir DIR       where to clone/find claude-red   (default: ~/claude-red)
  --out-dir DIR       audit report output dir          (default: <repo>/out)
  --dry-run           print actions without making changes
  --test              after installing, also run the smoke test
USAGE
}

say()  { printf '%s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
_do()  { if [ "$DRY_RUN" = 1 ]; then say "[dry-run] $*"; else "$@"; fi; }

# --- arg parsing ------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    install|test) CMD="$1" ;;
    --harness)    HARNESS="${2:-}"; shift ;;
    --red-dir)    RED_DIR="${2:-}"; shift ;;
    --out-dir)    OUT_DIR="${2:-}"; shift ;;
    --dry-run)    DRY_RUN=1 ;;
    --test)       DO_TEST=1 ;;
    -h|--help)    usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
  shift
done

RED_SKILLS="$RED_DIR/Skills"        # the skills dir the rendered agents point at
REPORTING_SKILL="$REPO_DIR/reporting/SKILL.md"   # vendored in-repo; NOT from claude-red

# --- helpers ----------------------------------------------------------------
_mkdir() { _do mkdir -p "$1"; }

_relink() { # _relink <target> <linkname> : replace any existing file/dir/symlink with a symlink
  local tgt="$1" link="$2"
  if [ "$DRY_RUN" = 1 ]; then say "[dry-run] ln -s $tgt $link (replacing any existing)"; return; fi
  rm -rf "$link"; ln -s "$tgt" "$link"
}

_prepdir() { # ensure $1 is a real, empty-of-our-files directory (drop a stale symlink first)
  if [ -L "$1" ]; then _do rm -f "$1"; fi
  _mkdir "$1"
}

_render() { # _render <src template> <dst> : substitute install-time tokens
  local src="$1" dst="$2"
  if [ "$DRY_RUN" = 1 ]; then say "[dry-run] render $(basename "$src") -> $dst"; return; fi
  sed -e "s#__RED_SKILLS__#$RED_SKILLS#g" -e "s#__OUT_DIR__#$OUT_DIR#g" -e "s#__REPORTING_SKILL__#$REPORTING_SKILL#g" "$src" > "$dst"
}

# --- install steps ----------------------------------------------------------
install_skills() {
  local d sparse=""
  for d in $DOMAINS; do sparse="$sparse Skills/$d"; done
  if [ -d "$RED_DIR/.git" ] || [ -d "$RED_DIR/Skills" ]; then
    say "==> reusing existing claude-red checkout at $RED_DIR"
    if [ -d "$RED_DIR/.git" ] && [ "$(git -C "$RED_DIR" config --get --bool core.sparseCheckout 2>/dev/null)" = "true" ]; then
      # shellcheck disable=SC2086  # $sparse is a controlled, space-separated path list
      _do git -C "$RED_DIR" sparse-checkout add $sparse || true
    fi
  else
    say "==> cloning claude-red (sparse: $DOMAINS) into $RED_DIR"
    _do git clone --filter=blob:none --sparse "$RED_URL" "$RED_DIR"
    # shellcheck disable=SC2086  # $sparse is a controlled, space-separated path list
    _do git -C "$RED_DIR" sparse-checkout set $sparse
  fi
  [ "$DRY_RUN" = 1 ] || [ -d "$RED_DIR/Skills" ] || die "no Skills/ directory under $RED_DIR"
  _mkdir "$OUT_DIR"
}

install_claude() {
  say "==> rendering Claude Code agents into ~/.claude/agents"
  _prepdir "$HOME/.claude/agents"
  local f
  for f in "$REPO_DIR"/claude/agents/*.md; do
    _render "$f" "$HOME/.claude/agents/$(basename "$f")"
  done
}

install_pi() {
  say "==> rendering pi agents into ~/.pi/agent and wiring the subagent extension"
  _prepdir "$HOME/.pi/agent/agents"
  local f
  for f in "$REPO_DIR"/pi/agents/*.md; do
    _render "$f" "$HOME/.pi/agent/agents/$(basename "$f")"
  done
  _prepdir "$HOME/.pi/agent/prompts"
  _render "$REPO_DIR/pi/prompts/websec.md" "$HOME/.pi/agent/prompts/websec.md"
  _mkdir "$HOME/.pi/agent/extensions"
  _relink "$REPO_DIR/pi/extensions/subagent" "$HOME/.pi/agent/extensions/subagent"
  # seed the gitignored backend config from the templates, then symlink it live
  [ -f "$REPO_DIR/pi/models.json" ]   || _do cp "$REPO_DIR/pi/models.example.json"   "$REPO_DIR/pi/models.json"
  [ -f "$REPO_DIR/pi/settings.json" ] || _do cp "$REPO_DIR/pi/settings.example.json" "$REPO_DIR/pi/settings.json"
  _relink "$REPO_DIR/pi/models.json"   "$HOME/.pi/agent/models.json"
  _relink "$REPO_DIR/pi/settings.json" "$HOME/.pi/agent/settings.json"
  say "    pi backend config: edit $REPO_DIR/pi/models.json to point at your LLM endpoint"
}

do_install() {
  if [ -z "$HARNESS" ]; then
    if [ -t 0 ]; then
      printf 'Install which harness? [both/claude/pi] (both): '
      read -r ans || ans=""
      HARNESS="${ans:-both}"
    else
      HARNESS="both"
    fi
  fi
  case "$HARNESS" in pi|claude|both) ;; *) die "--harness must be pi, claude, or both (got '$HARNESS')" ;; esac

  install_skills
  [ "$HARNESS" = claude ] || [ "$HARNESS" = both ] && install_claude || true
  [ "$HARNESS" = pi ]     || [ "$HARNESS" = both ] && install_pi     || true

  say ""
  say "Done. Harness: $HARNESS | skills: $RED_SKILLS | output: $OUT_DIR"
  say "Verify wiring:  ./setup.sh test"
  say "Run (Claude):   ask web-orchestrator: 'target=http://HOST:PORT classes=jwt,ssrf'  (or plain English)"
  [ "$HARNESS" = claude ] || say "Run (pi):       /websec target=http://HOST:PORT classes=jwt,ssrf   (or describe it in plain English)"
}

# --- smoke test (non-destructive, no network) -------------------------------
smoke_test() {
  local fail=0 pass_c=0
  _ck() { # _ck <ok 0/1> <description>
    if [ "$1" = 0 ]; then say "  PASS  $2"; pass_c=$((pass_c+1)); else say "  FAIL  $2"; fail=1; fi
  }
  say "== skills resolve (offensive-* under each installed domain) =="
  local domain skill n
  for domain in $DOMAINS; do
    n=0
    for skill in "$RED_SKILLS/$domain"/offensive-*/SKILL.md; do
      [ -r "$skill" ] || continue
      n=$((n+1)); _ck 0 "$domain/$(basename "$(dirname "$skill")")"
    done
    [ "$n" != 0 ] || _ck 1 "$domain: no readable offensive-*/SKILL.md under $RED_SKILLS/$domain"
  done

  say "== reporter skill (vendored in repo) =="
  if [ -r "$REPORTING_SKILL" ]; then _ck 0 "reporting/SKILL.md"; else _ck 1 "reporting/SKILL.md  ($REPORTING_SKILL)"; fi

  say "== rendered agents have no unsubstituted tokens =="
  local f found=0
  for f in "$HOME"/.claude/agents/web-*.md "$HOME"/.pi/agent/agents/web-*.md "$HOME"/.pi/agent/prompts/websec.md; do
    [ -f "$f" ] || continue
    found=1
    if grep -q '__RED_SKILLS__\|__OUT_DIR__\|__REPORTING_SKILL__' "$f"; then _ck 1 "leftover token in $f"; else _ck 0 "$f"; fi
  done
  [ "$found" = 1 ] || say "  (no rendered agent files found — run ./setup.sh install first)"

  if [ -e "$HOME/.pi/agent/extensions/subagent" ]; then
    say "== pi subagent extension =="
    if [ -d "$HOME/.pi/agent/extensions/subagent" ]; then _ck 0 "subagent symlink resolves"; else _ck 1 "subagent symlink is broken"; fi
  fi

  say ""
  if [ "$fail" = 0 ]; then say "SMOKE TEST PASSED ($pass_c checks)"; else say "SMOKE TEST FAILED"; return 1; fi
}

# --- dispatch ---------------------------------------------------------------
case "$CMD" in
  test)    smoke_test ;;
  install) do_install; [ "$DO_TEST" = 1 ] && { say ""; smoke_test; } || true ;;
esac
