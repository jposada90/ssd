#!/usr/bin/env bash
# Install the SDD agent suite into one or more harnesses.
#
#   ./install.sh --claude                 install for Claude Code, globally
#   ./install.sh --opencode --project     install for OpenCode, in this project
#   ./install.sh --all                    every harness, globally
#   ./install.sh --check --claude         report what is installed, change nothing
#   ./install.sh --claude --uninstall     remove what this installer added
#
# Run with no flags to see usage.
set -uo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
AGENTS_SRC="$SRC/agents"
GLOBAL_SUITE="${XDG_CONFIG_HOME:-$HOME/.config}/sdd-agents"
ROOT_POINTER="$GLOBAL_SUITE/root"

HARNESSES=()
SCOPE="global"
DO_CHECK=0
DO_UNINSTALL=0
DO_SKILLS=1
FORCE=0

usage() {
  sed -n '3,10p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'EOF'

Options:
  --claude | --opencode | --pi    which harnesses (repeatable)
  --all                           every harness
  --global | --project            user-level (default) or project-level
  --check                         report installation state, change nothing
  --uninstall                     remove agent files this installer added
  --skills | --no-skills          link the optional skills (default: link)
  --source <dir>                  where the suite lives (default: this script's dir)
  --force                         overwrite files that already exist
EOF
}

project_root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }

# The Conductor finds its own scripts and the roadmap schema from here. One copy
# per scope, shared by every harness.
suite_root() {
  if [ "$SCOPE" = "global" ]; then
    echo "$GLOBAL_SUITE/suite"
  else
    echo "$(project_root)/.sdd/agents"
  fi
}

harness_paths() {
  case "$1" in
    claude)
      if [ "$SCOPE" = project ]; then echo "$(project_root)/.claude|$(project_root)/.claude/agents"
      else echo "$HOME/.claude|$HOME/.claude/agents"; fi ;;
    opencode)
      if [ "$SCOPE" = project ]; then echo "$(project_root)/.opencode|$(project_root)/.opencode/agents"
      else echo "$HOME/.config/opencode|$HOME/.config/opencode/agents"; fi ;;
    pi)
      if [ "$SCOPE" = project ]; then echo "$(project_root)/.pi|$(project_root)/.pi/agents"
      else echo "$HOME/.pi|$HOME/.pi/agent/agents"; fi ;;
  esac
}

skills_dir() {
  case "$1" in
    claude)   echo "$HOME/.claude/skills" ;;
    opencode) echo "$HOME/.config/opencode/skills" ;;
    pi)       echo "$HOME/.pi/agent/skills" ;;
  esac
}

report() {
  local h agents_dir suite missing=0
  suite="$(suite_root)"
  for h in "${HARNESSES[@]}"; do
    IFS='|' read -r _ agents_dir <<<"$(harness_paths "$h")"
    echo "== $h ($SCOPE)"
    if [ -d "$agents_dir" ]; then
      echo "   agents:  $agents_dir ($(find "$agents_dir" -maxdepth 1 -name '*.md' | wc -l) file(s))"
    else
      echo "   agents:  $agents_dir (missing)"
      missing=$((missing + 1))
    fi
  done
  echo
  echo "   suite:   $suite"
  if [ -f "$suite/conductor/versions.json" ]; then
    echo "            present"
  else
    echo "            absent"
    missing=$((missing + 1))
  fi
  echo "   pointer: $ROOT_POINTER -> $(cat "$ROOT_POINTER" 2>/dev/null || echo none)"
  echo
  [ "$missing" -eq 0 ] && { echo "CHECK OK"; return 0; }
  echo "CHECK INCOMPLETE: $missing problem(s)"
  return 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --claude)     HARNESSES+=(claude) ;;
    --opencode)   HARNESSES+=(opencode) ;;
    --pi)         HARNESSES+=(pi) ;;
    --all)        HARNESSES=(claude opencode pi) ;;
    --global)     SCOPE="global" ;;
    --project)    SCOPE="project" ;;
    --check)      DO_CHECK=1 ;;
    --uninstall)  DO_UNINSTALL=1 ;;
    --skills)     DO_SKILLS=1 ;;
    --no-skills)  DO_SKILLS=0 ;;
    --force)      FORCE=1 ;;
    --source)
      if [ $# -lt 2 ]; then echo "error: --source needs a value" >&2; exit 2; fi
      SRC="$2"; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$DO_CHECK" = 1 ]; then
  if [ ${#HARNESSES[@]} -eq 0 ]; then
    HARNESSES=(claude opencode pi)
    echo "note: no harness given, checking all three. Pass --claude to check only one."
    echo
  fi
  report
  exit $?
fi

if [ ${#HARNESSES[@]} -eq 0 ]; then
  echo "error: choose at least one harness" >&2; echo >&2; usage >&2; exit 2
fi

if [ ! -f "$SRC/build.mjs" ] || [ ! -d "$AGENTS_SRC" ]; then
  echo "error: $SRC is not the agent suite." >&2
  echo "       expected build.mjs and agents/ side by side." >&2
  echo "       pass --source <repo root> if running from elsewhere." >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  echo "error: node is required to render the agent files." >&2
  echo "       the rendered files ship in dist/, but --check regenerates them." >&2
  exit 2
fi

if ! node "$SRC/build.mjs" --check >/dev/null 2>&1; then
  echo "note: rendered files were stale, rebuilding"
  node "$SRC/build.mjs" >/dev/null || { echo "error: build failed" >&2; exit 1; }
fi

# --- suite: once per scope, shared by every harness ---------------------------
# On uninstall it is removed only after the agent files are gone, and only when
# no harness in this scope still has the suite installed.
suite="$(suite_root)"

if [ "$DO_UNINSTALL" = 0 ]; then
  mkdir -p "$suite"
  for a in conductor task-decomposer; do
    [ -d "$AGENTS_SRC/$a" ] || continue
    rm -rf "$suite/$a"
    cp -r "$AGENTS_SRC/$a" "$suite/$a"
    # dist/ belongs to the harness install, and caches are never worth shipping.
    rm -rf "$suite/$a/dist"
    find "$suite/$a" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null
  done
  echo "suite   $suite"
  if [ "$SCOPE" = "global" ]; then
    mkdir -p "$(dirname "$ROOT_POINTER")"
    printf '%s\n' "$suite" > "$ROOT_POINTER"
    echo "pointer $ROOT_POINTER -> $suite"
  fi
fi

# --- agent files: flat, one per harness ---------------------------------------
installed=()

for h in "${HARNESSES[@]}"; do
  IFS='|' read -r _ agents_dir <<<"$(harness_paths "$h")"
  mkdir -p "$agents_dir"

  for src in "$AGENTS_SRC"/*/dist/"$h"/*.md; do
    [ -e "$src" ] || continue
    dest="$agents_dir/$(basename "$src")"
    if [ "$DO_UNINSTALL" = 1 ]; then
      if [ -e "$dest" ]; then rm -f "$dest"; echo "removed $dest"; fi
      continue
    fi
    if [ -e "$dest" ] && [ "$FORCE" != 1 ]; then
      echo "exists  $dest (--force to overwrite)"
      continue
    fi
    cp "$src" "$dest"
    installed+=("$dest")
  done

  # Optional skills, linked so one update reaches every harness.
  if [ "$DO_SKILLS" = 1 ] && [ "$DO_UNINSTALL" = 0 ]; then
    sdir="$(skills_dir "$h")"
    for skill in writing-for-agents; do
      src="$HOME/.agents/skills/$skill"
      if [ ! -d "$src" ]; then
        echo "missing skill $skill for $h"
        echo "        npx skills add mattpocock/skills --skill $skill --global --yes"
        continue
      fi
      mkdir -p "$sdir"
      if [ -e "$sdir/$skill" ] || [ -L "$sdir/$skill" ]; then continue; fi
      ln -s "$src" "$sdir/$skill"
      echo "skill   $sdir/$skill"
    done
  fi
done

if [ "$DO_UNINSTALL" = 0 ]; then
  for f in "${installed[@]}"; do echo "agent   $f"; done
  echo
  echo "Installed ${#installed[@]} agent file(s). Restart the harness to pick them up."
else
  # The suite is shared by every harness in this scope, so it survives until the
  # last one leaves. Removing it early would strand the remaining agents with
  # no scripts to call.
  still=""
  for h in claude opencode pi; do
    IFS='|' read -r _ dir <<<"$(harness_paths "$h")"
    if [ -f "$dir/conductor.md" ]; then
      still="$still $h"
    fi
  done
  if [ -n "$still" ]; then
    echo
    echo "suite kept at $suite (still used by:$still)"
  else
    [ -d "$suite" ] && { rm -rf "$suite"; echo "removed $suite"; }
    if [ "$SCOPE" = "global" ]; then
      [ -f "$ROOT_POINTER" ] && { rm -f "$ROOT_POINTER"; echo "removed $ROOT_POINTER"; }
    fi
  fi
fi