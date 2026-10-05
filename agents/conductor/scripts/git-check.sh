#!/usr/bin/env bash
# SDD preflight: git working tree state. Uncommitted work is a decision for the
# user, not something to clean up automatically.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 2

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "branch: $branch"

  staged="$(git diff --cached --name-only)"
  unstaged="$(git diff --name-only)"
  untracked="$(git ls-files --others --exclude-standard)"

  if [ -z "$staged" ] && [ -z "$unstaged" ] && [ -z "$untracked" ]; then
    echo "state: clean"
    echo "GIT OK"
    exit 0
  fi

  echo "state: DIRTY"
  [ -n "$staged" ]   && { echo "staged:";   echo "$staged"   | sed 's/^/  /'; }
  [ -n "$unstaged" ] && { echo "modified:"; echo "$unstaged" | sed 's/^/  /'; }
  [ -n "$untracked" ] && { echo "untracked:"; echo "$untracked" | sed 's/^/  /'; }

  echo
  echo "GIT DIRTY"
  exit 1
fi

echo "not a git repository"
echo "GIT MISSING"
exit 2