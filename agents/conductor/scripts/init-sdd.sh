#!/usr/bin/env bash
# SDD init: create the project scaffold the Conductor needs.
#   AGENTS.md      the durable project contract (written once, edited by hand)
#   roadmap/       the task tree, with its schema and checker
#   changes/       per-task working documents, archived into doc/ when done
#   doc/es, doc/en archived documents and their translations
#   doc/glossary.md terminology, so translations and code use the same words
#   symlinks       harness entry points that point at AGENTS.md
#
# Idempotent: existing files are never overwritten.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 2

AGENT_SRC="${AGENT_SRC:-}"
AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# The roadmap schema travels with the suite, so this normally needs no argument.
# Override ROADMAP_SRC when running straight from a checkout that has it elsewhere.
if [ -z "${ROADMAP_SRC:-}" ]; then
  for candidate in "$AGENT_DIR/../task-decomposer/schema" "$AGENT_DIR/schema"; do
    if [ -f "$candidate/roadmap.schema.json" ]; then
      ROADMAP_SRC="$(cd "$candidate" && pwd)"
      break
    fi
  done
fi

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

created=()

if [ ! -f AGENTS.md ] || [ "$FORCE" = 1 ]; then
  if [ -n "$AGENT_SRC" ] && [ -f "$AGENT_SRC" ]; then
    cp "$AGENT_SRC" AGENTS.md
    created+=("AGENTS.md")
  else
    cat > AGENTS.md <<'EOF'
# AGENTS.md

Durable instructions for agents working on this repository. Read this before
touching code. It is the contract, not a status report.

## Project

Describe what this project is, in two or three sentences.

## Verification

Declare the commands that prove the project works. `scripts/preflight.sh` reads
these lines and runs them; leave a command blank to skip that check.

```
build:
test:
lint:
typecheck:
format:
```

## Conventions

Commands, naming, and patterns an agent would otherwise get wrong. Keep it
short: what is non-obvious, and what the environment cannot tell you.

## Working agreement

- Work flows through the roadmap under `roadmap/`. One task at a time.
- Do not commit unless asked. The Conductor owns git and the SDD cycle.
- Working documents live in `changes/<task-id>/`; archived ones in `doc/es/`.
- Terms in `doc/glossary.md` are the project's vocabulary. Use them.

## SDD

The project follows a Spec-Driven Development cycle: proposal, specs, design,
task, apply, verify, archive. `scripts/preflight.sh`, `scripts/git-check.sh` and
`scripts/i18n-check.sh` verify the repo state before any of it starts.
EOF
    created+=("AGENTS.md")
  fi
fi

mkdir -p changes doc/es doc/en roadmap/issues
created+=("changes/" "doc/es/" "doc/en/" "roadmap/issues/")

if [ ! -f doc/glossary.md ]; then
  cat > doc/glossary.md <<'EOF'
# Glossary

The project's vocabulary. Code, documentation and translations all use these
words. When a term is ambiguous, fix it here first.

| Term | Definition | Avoid |
|---|---|---|
| | | |
EOF
  created+=("doc/glossary.md")
fi

if [ -n "$ROADMAP_SRC" ] && [ -f "$ROADMAP_SRC/roadmap.schema.json" ] && [ ! -f roadmap/schema/roadmap.schema.json ]; then
  mkdir -p roadmap/schema
  cp "$ROADMAP_SRC/roadmap.schema.json" roadmap/schema/
  created+=("roadmap/schema/roadmap.schema.json")
fi

if [ -n "$ROADMAP_SRC" ] && [ -f "$ROADMAP_SRC/check_roadmap.py" ] && [ ! -f roadmap/schema/check_roadmap.py ]; then
  cp "$ROADMAP_SRC/check_roadmap.py" roadmap/schema/
  chmod +x roadmap/schema/check_roadmap.py 2>/dev/null
  created+=("roadmap/schema/check_roadmap.py")
fi

if [ ! -f roadmap/main.json ]; then
  if [ -n "$ROADMAP_SRC" ] && [ -f "$ROADMAP_SRC/main.json" ]; then
    cp "$ROADMAP_SRC/main.json" roadmap/main.json
  else
    cp "$(dirname "$0")/../main.json.template" roadmap/main.json 2>/dev/null || {
      echo "no main.json template found; create roadmap/main.json by hand" >&2
    }
  fi
  [ -f roadmap/main.json ] && created+=("roadmap/main.json")
fi

# Harness entry points. Each tool reads a different filename; one source of truth.
# The target is relative to the symlink's own directory, so a link inside a
# subdirectory needs ../ to reach the root.
link_to_agents() {
  local link="$1" depth
  mkdir -p "$(dirname "$link")"
  depth="$(dirname "$link")"
  local target="AGENTS.md"
  while [ "$depth" != "." ] && [ "$depth" != "/" ]; do
    target="../$target"
    depth="$(dirname "$depth")"
  done
  ln -s "$target" "$link"
  created+=("$link -> $target")
}

for link in CLAUDE.md GEMINI.md .cursorrules .github/copilot-instructions.md; do
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    link_to_agents "$link"
  fi
done

# The preflight scripts live in the project, so the cycle is verifiable without
# this repository present.
mkdir -p scripts
for s in preflight.sh git-check.sh i18n-check.sh sdd_check.py models.py; do
  if [ -f "$AGENT_DIR/scripts/$s" ] && [ ! -f "scripts/$s" ]; then
    cp "$AGENT_DIR/scripts/$s" scripts/
    chmod +x "scripts/$s" 2>/dev/null
    created+=("scripts/$s")
  fi
done

# sdd.json records which SDD version last touched this project, and the layout it
# declared. sdd_check.py compares both against the agent's versions.json.
if [ ! -f sdd.json ] || [ "$FORCE" = 1 ]; then
  SDD_VERSION="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['current'])" "$AGENT_DIR/versions.json")"
  python3 - "$AGENT_DIR/versions.json" "$SDD_VERSION" "$(date -u +%Y-%m-%d)" <<'PY'
import json, sys
versions_path, version, today = sys.argv[1], sys.argv[2], sys.argv[3]
layout = json.load(open(versions_path))["versions"][version]["layout"]
doc = {
    "sddVersion": version,
    "initializedAt": today,
    "layout": {k: v for k, v in layout.items() if k != "symlinks"},
    "models": {},
}
with open("sdd.json", "w") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
  created+=("sdd.json")
fi

if [ ${#created[@]} -gt 0 ]; then
  echo "== created"
  printf '  %s\n' "${created[@]}"
else
  echo "== nothing to do; scaffold already present"
fi

echo
echo "Fill in the Verification block of AGENTS.md before running preflight."