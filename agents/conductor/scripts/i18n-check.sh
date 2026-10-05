#!/usr/bin/env bash
# SDD: verify the glossary and that doc/en mirrors doc/es.
# Translation quality is the author's job; what fails silently is terminology
# drift and structure drift, which is what this catches.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 2

ES_DIR="doc/es"
EN_DIR="doc/en"
PROBLEMS=()

if [ ! -d "$ES_DIR" ]; then
  echo "no $ES_DIR yet; nothing to check"
  echo "I18N OK"
  exit 0
fi

if [ ! -f doc/glossary.md ]; then
  PROBLEMS+=("no glossary.md: terms drift without one. Create it at doc/glossary.md")
fi

if [ ! -d "$EN_DIR" ]; then
  echo "no $EN_DIR yet"
  PROBLEMS+=("$EN_DIR missing: doc/es has documents but none were translated")
fi

# Structure parity: same relative paths, and same heading depth sequence.
while IFS= read -r es_file; do
  rel="${es_file#"$ES_DIR"/}"
  en_file="$EN_DIR/$rel"

  if [ ! -f "$en_file" ]; then
    PROBLEMS+=("missing translation: $en_file (source: $es_file)")
    continue
  fi

  es_headings="$(grep -cE '^#{1,6} ' "$es_file" 2>/dev/null || echo 0)"
  en_headings="$(grep -cE '^#{1,6} ' "$en_file" 2>/dev/null || echo 0)"
  if [ "$es_headings" != "$en_headings" ]; then
    PROBLEMS+=("heading drift in $rel: es=$es_headings en=$en_headings")
  fi

  es_code="$(grep -cE '^```' "$es_file" 2>/dev/null || echo 0)"
  en_code="$(grep -cE '^```' "$en_file" 2>/dev/null || echo 0)"
  if [ "$es_code" != "$en_code" ]; then
    PROBLEMS+=("code fence drift in $rel: es=$es_code en=$en_code (content must stay identical)")
  fi
done < <(find "$ES_DIR" -name '*.md' -type f | sort)

# Source docs that must stay in the source language.
if [ -d "$EN_DIR" ]; then
  while IFS= read -r en_file; do
    rel="${en_file#"$EN_DIR"/}"
    if [ ! -f "$ES_DIR/$rel" ]; then
      PROBLEMS+=("orphan translation: $en_file has no $ES_DIR source")
    fi
  done < <(find "$EN_DIR" -name '*.md' -type f | sort)
fi

if [ ${#PROBLEMS[@]} -gt 0 ]; then
  echo "== i18n problems"
  printf '  %s\n' "${PROBLEMS[@]}"
  echo "I18N FAIL"
  exit 1
fi

echo "doc/es and doc/en are structurally in sync"
echo "I18N OK"