#!/usr/bin/env bash
# SDD preflight: build, test and type/lint checks for the project.
# Reads the commands declared in AGENTS.md under the "Verification" heading.
# Exits non-zero on failure; the Conductor reports and never repairs here.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 2

declare -A CMD=(
  [build]=""
  [test]=""
  [lint]=""
  [format]=""
  [typecheck]=""
)

# Read one command per line from the Verification block of AGENTS.md.
# Format inside AGENTS.md:  build: npm run build
if [ -f AGENTS.md ]; then
  while IFS= read -r line; do
    case "$line" in
      "build: "*)    CMD[build]="${line#build: }" ;;
      "test: "*)     CMD[test]="${line#test: }" ;;
      "lint: "*)     CMD[lint]="${line#lint: }" ;;
      "format: "*)   CMD[format]="${line#format: }" ;;
      "typecheck: "*) CMD[typecheck]="${line#typecheck: }" ;;
    esac
  done < <(sed -n '/^## Verification/,/^## /p' AGENTS.md | grep -E '^(build|test|lint|format|typecheck): ')
fi

# Fall back to the common manifest scripts when AGENTS.md declares nothing.
if [ -z "${CMD[test]}" ] && [ -f package.json ]; then
  CMD[test]="npm test"
fi

FAILED=()
SKIPPED=()

run_check() {
  local name="$1" cmd="${CMD[$1]}"
  if [ -z "$cmd" ]; then
    SKIPPED+=("$name")
    printf 'SKIP %s (not declared in AGENTS.md)\n' "$name"
    return 0
  fi
  printf '\n=== %s: %s\n' "$name" "$cmd"
  if eval "$cmd"; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s (exit %d)\n' "$name" "$?"
    FAILED+=("$name")
    return 1
  fi
}

echo "== SDD preflight: $(pwd)"

run_check build
run_check test
run_check lint
run_check typecheck

# format is a check-only variant: many projects have no format:check script
if [ -n "${CMD[format]}" ]; then
  run_check format
elif [ -f package.json ] && grep -q '"format' package.json; then
  SKIPPED+=("format")
  printf '\nNOTE format: script exists but no format check declared. Declare "format:" in AGENTS.md.\n'
fi

echo
echo "== preflight summary"
printf 'failed:  %s\n' "${FAILED[*]:-none}"
printf 'skipped: %s\n' "${SKIPPED[*]:-none}"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo "PREFLIGHT FAILED"
  exit 1
fi
echo "PREFLIGHT OK"