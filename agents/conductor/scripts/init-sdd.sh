#!/usr/bin/env bash
# SDD init: create the project scaffold the Conductor needs.
#
# Versioned, because the team shares them:
#   AGENTS.md        the durable project contract (written once, edited by hand)
#   roadmap/         the task tree, plus the schema that defines its documents
#   changes/         per-task working documents, archived into doc/ when done
#   doc/es, doc/en   archived documents and their translations
#   doc/glossary.md  terminology, so translations and code use the same words
#   entry points     CLAUDE.md etc. for the harnesses you pick, pointing at AGENTS.md
#
# Local to the machine, under .sdd/ and gitignored:
#   .sdd/sdd.json    which SDD version last touched this project, its layout,
#                    which harnesses it chose, and the user's model choices
#   .sdd/scripts/    the scripts the agents run
#
# Nothing outside .sdd/ and the scaffold above is written. Phase agents never
# touch .sdd/: it is the Conductor's own state, and a subagent editing its own
# controls is how a cycle quietly stops being checked.
#
# Usage:
#   init-sdd.sh                       asks which harnesses, if on a terminal
#   init-sdd.sh --for claude,copilot  skips the question
#   init-sdd.sh --force               overwrite files that already exist
#
# Idempotent: existing files are never overwritten.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 2

AGENT_SRC="${AGENT_SRC:-}"
AGENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FOR=""

# The roadmap schema travels with the suite, so this normally needs no argument.
# A copy living in .sdd/scripts has no suite to look at, but the project itself has
# the schema under roadmap/schema/, which is the right place to read it from.
if [ -z "${ROADMAP_SRC:-}" ]; then
  for candidate in "$AGENT_DIR/../task-decomposer/schema" "roadmap/schema" "$AGENT_DIR/schema"; do
    if [ -f "$candidate/roadmap.schema.json" ]; then
      ROADMAP_SRC="$(cd "$candidate" && pwd)"
      break
    fi
  done
fi

FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --for) shift; [ $# -gt 0 ] && FOR="${1//,/ }" || { echo "error: --for needs a value" >&2; exit 2; } ;;
    --for=*) FOR="${1#--for=}"; FOR="${FOR//,/ }" ;;
    -h|--help) sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

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

Declare the commands that prove the project works. `.sdd/scripts/preflight.sh` reads
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
- `.sdd/` is the Conductor's own state and is gitignored. Never read it, write it,
  or run anything that edits it: the Conductor owns it, and a subagent changing its
  own controls is how a cycle quietly stops being checked.

## SDD

The project follows a Spec-Driven Development cycle: proposal, specs, design,
task, apply, verify, archive. `.sdd/scripts/preflight.sh`,
`.sdd/scripts/git-check.sh` and `.sdd/scripts/i18n-check.sh` verify the repo state
before any of it starts.
EOF
    created+=("AGENTS.md")
  fi
fi

mkdir -p changes doc/es doc/en roadmap/issues changes/archive
created+=("changes/" "changes/archive/" "doc/es/" "doc/en/" "roadmap/issues/")

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

if [ ! -f roadmap/main.json ]; then
  if [ -n "$ROADMAP_SRC" ] && [ -f "$ROADMAP_SRC/main.json" ]; then
    cp "$ROADMAP_SRC/main.json" roadmap/main.json
  else
    # Branch names come from the repo, not from a guess: hardcoding `main`
    # writes false git info into the roadmap on a `master` repo.
    # A branch name, never the literal "HEAD" that git reports when the branch is
    # unborn or origin/HEAD is unresolved.
    is_branch() { [ -n "$1" ] && [ "$1" != "HEAD" ]; }

    current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    if ! is_branch "$current_branch"; then
      # Unborn branch: rev-parse reports HEAD, but .git/HEAD still names it.
      current_branch="$(sed -n 's|^ref: refs/heads/||p' .git/HEAD 2>/dev/null | head -1)"
    fi

    default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
    default_branch="${default_branch#origin/}"
    if ! is_branch "$default_branch"; then
      # No remote to ask, so the checked-out branch is the best evidence.
      default_branch="$current_branch"
    fi
    if ! is_branch "$default_branch"; then
      default_branch="$(git config --get init.defaultBranch 2>/dev/null)"
      is_branch "$default_branch" || default_branch="main"
    fi
    is_branch "$current_branch" || current_branch="$default_branch"

    sed -e "s|__DEFAULT_BRANCH__|$default_branch|g" \
        -e "s|__CURRENT_BRANCH__|$current_branch|g" \
        "$(dirname "$0")/../main.json.template" > roadmap/main.json 2>/dev/null || {
      echo "no main.json template found; create roadmap/main.json by hand" >&2
    }
  fi
  [ -f roadmap/main.json ] && created+=("roadmap/main.json")
fi

# --- entry points: ask which harnesses this project is for -------------------
# Linking all four by default litters the repo with files nobody uses, and a
# stale CLAUDE.md is worse than none.
LINK_OPTIONS="claude:CLAUDE.md gemini:GEMINI.md cursor:.cursorrules copilot:.github/copilot-instructions.md"

# Prints the menu on stderr and only the chosen names on stdout, so the caller can
# capture a selection with $(...) without swallowing the question.
ask_links() {
  local n=1 line name path reply token idx chosen
  {
    echo
    echo "Which harnesses will work on this repository?"
    echo "Each gets its own entry point pointing at AGENTS.md."
    echo
    for line in $LINK_OPTIONS; do
      name="${line%%:*}"
      path="${line#*:}"
      printf '  %d) %-8s %s\n' "$n" "$name" "$path"
      n=$((n + 1))
    done
    echo
    echo "Answer with names or numbers, separated by comma or space (e.g. claude, 3)."
    echo "'none' for no links. An empty answer takes all of them."
    printf '> '
  } >&2

  read -r reply || reply=""
  reply="${reply//,/ }"

  case "$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    none|nada|no) return 0 ;;
  esac
  [ -z "$(printf '%s' "$reply" | tr -d '[:space:]')" ] && {
    printf '%s\n' $LINK_OPTIONS | cut -d: -f1 | tr '\n' ' '
    return 0
  }

  chosen=""
  for token in $reply; do
    if [[ "$token" =~ ^[0-9]+$ ]]; then
      idx="$token"
      if [ "$idx" -ge 1 ] 2>/dev/null && [ "$idx" -le 4 ] 2>/dev/null; then
        line="$(printf '%s\n' $LINK_OPTIONS | sed -n "${idx}p")"
        chosen="$chosen ${line%%:*}"
      else
        echo "ignoring out-of-range selection: $idx" >&2
      fi
    else
      chosen="$chosen $(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
    fi
  done
  printf '%s\n' $chosen
}

# Resolve harness names to link paths using the agent's catalogue.
resolve_links() {
  python3 - "$AGENT_DIR/versions.json" "$AGENT_VERSION" "$1" <<'PY'
import json, sys
versions_path, version, wanted = sys.argv[1], sys.argv[2], sys.argv[3].split()
options = json.load(open(versions_path))["versions"][version]["linkOptions"]
for name in options:
    if name in wanted:
        print(f"{name}:{options[name]}")
PY
}

AGENT_VERSION="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['current'])" "$AGENT_DIR/versions.json")"

wanted=""
links_decided=0
if [ -n "$FOR" ]; then
  wanted="$FOR"
  links_decided=1
elif [ -t 0 ]; then
  # Keep the separators: joining names would fuse them into one unmatchable token.
  wanted="$(ask_links | tr '\n' ' ')"
  links_decided=1
else
  echo
  echo "note: not a terminal, so no harness was chosen."
  echo "      .sdd/sdd.json records links as undecided until you say which, e.g."
  echo "      init-sdd.sh --for claude,copilot    (or --for none)"
fi

# The target is relative to the symlink's own directory, so a link inside a
# subdirectory needs ../ to reach the root.
link_to_agents() {
  local link="$1" depth target
  mkdir -p "$(dirname "$link")"
  depth="$(dirname "$link")"
  target="AGENTS.md"
  while [ "$depth" != "." ] && [ "$depth" != "/" ]; do
    target="../$target"
    depth="$(dirname "$depth")"
  done
  ln -s "$target" "$link"
  created+=("$link -> $target")
}

chosen_links=""
if [ -n "$wanted" ]; then
  chosen_links="$(resolve_links "$wanted")"
  if [ -z "$chosen_links" ]; then
    echo "warning: none of '$wanted' matched a known harness; known: claude gemini cursor copilot" >&2
  fi
  while IFS=: read -r name link; do
    [ -n "$link" ] || continue
    if [ -e "$link" ] || [ -L "$link" ]; then
      echo "exists  $link"
    else
      link_to_agents "$link"
    fi
  done <<< "$chosen_links"
fi

# --- .sdd/: local state and scripts, gitignored -------------------------------
SDD_DIR=".sdd"
SDD_SCRIPTS="$SDD_DIR/scripts"

mkdir -p "$SDD_SCRIPTS"
created+=("$SDD_DIR/" "$SDD_SCRIPTS/")

# The scripts live in the project so the cycle is verifiable without this repo, and
# under .sdd/ so they are machine-local rather than something the team inherits.
for s in init-sdd.sh preflight.sh git-check.sh i18n-check.sh sdd_check.py migrate_sdd.py models.py; do
  if [ -f "$AGENT_DIR/scripts/$s" ] && [ ! -f "$SDD_SCRIPTS/$s" ]; then
    cp "$AGENT_DIR/scripts/$s" "$SDD_SCRIPTS/$s"
    chmod +x "$SDD_SCRIPTS/$s" 2>/dev/null
    created+=("$SDD_SCRIPTS/$s")
  fi
done

# check_roadmap.py is the schema's companion, so it travels from the same place,
# but it is tooling: it writes TreeTask.md, so it belongs with the scripts.
if [ -n "$ROADMAP_SRC" ] && [ -f "$ROADMAP_SRC/check_roadmap.py" ] && [ ! -f "$SDD_SCRIPTS/check_roadmap.py" ]; then
  cp "$ROADMAP_SRC/check_roadmap.py" "$SDD_SCRIPTS/"
  chmod +x "$SDD_SCRIPTS/check_roadmap.py" 2>/dev/null
  created+=("$SDD_SCRIPTS/check_roadmap.py")
fi

# .sdd/ must never be committed. Adding it here means nobody can forget and then
# leak local model choices and absolute paths into the team's history.
if [ -f .gitignore ]; then
  if ! grep -qxF '.sdd/' .gitignore 2>/dev/null; then
    printf '\n# Local SDD state: suite config and scripts. Never commit.\n.sdd/\n' >> .gitignore
    created+=(".gitignore (.sdd/)")
  fi
else
  printf '.sdd/\n' > .gitignore
  created+=(".gitignore (.sdd/)")
fi

# .sdd/sdd.json records which SDD version last touched this project, the layout it
# declared, which entry points it chose, and the user's model choices.
if [ ! -f "$SDD_DIR/sdd.json" ] || [ "$FORCE" = 1 ]; then
  python3 - "$AGENT_DIR/versions.json" "$AGENT_VERSION" "$(date -u +%Y-%m-%d)" "$chosen_links" "$links_decided" <<'PY'
import json, sys
versions_path, version, today, chosen, decided = sys.argv[1:6]
spec = json.load(open(versions_path))["versions"][version]
# [] means "deliberately none"; null means "nobody has decided yet". Those are
# different states, so sdd_check.py rejects null and sends the question back.
if decided == "1":
    links = [line.split(":", 1)[1] for line in chosen.split() if ":" in line]
else:
    links = None
doc = {
    "sddVersion": version,
    "initializedAt": today,
    "layout": {k: v for k, v in spec["layout"].items() if k != "symlinks"},
    "links": links,
    "models": {},
}
with open(".sdd/sdd.json", "w") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
  created+=("$SDD_DIR/sdd.json")
fi

if [ ${#created[@]} -gt 0 ]; then
  echo "== created"
  printf '  %s\n' "${created[@]}"
else
  echo "== nothing to do; scaffold already present"
fi

echo
echo "Fill in the Verification block of AGENTS.md before running preflight."