#!/usr/bin/env bash
# SDD: verify the glossary and that doc/en mirrors doc/es.
# Translation quality is the author's job; what fails silently is terminology
# drift and structure drift, which is what this catches.
# Supports translated filenames via a mapping table.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" || exit 2

ES_DIR="doc/es"
EN_DIR="doc/en"
PROBLEMS=()

# Mapping of Spanish filenames to English equivalents
# Format: "es_path:en_path" (relative to doc/ directories)
declare -A TRANSLATION_MAP=(
  ["TASK-0001-resumen.md"]="TASK-0001-summary.md"
  ["estado-roadmap.md"]="roadmap-status.md"
)

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

# Helper function to find translated filename
find_translated_file() {
  local es_rel="$1"
  # Check if there's a mapping for this file
  if [ -n "${TRANSLATION_MAP[$es_rel]:-}" ]; then
    echo "${EN_DIR}/${TRANSLATION_MAP[$es_rel]}"
  else
    echo "${EN_DIR}/$es_rel"
  fi
}

# Structure parity: same relative paths, and same heading depth sequence.
while IFS= read -r es_file; do
  rel="${es_file#"$ES_DIR"/}"
  en_file="$(find_translated_file "$rel")"

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

# Helper function to find source filename (reverse mapping)
find_source_file() {
  local en_rel="$1"
  # Check if this file is a target in the mapping
  for es_key in "${!TRANSLATION_MAP[@]}"; do
    if [ "${TRANSLATION_MAP[$es_key]}" = "$en_rel" ]; then
      echo "${ES_DIR}/$es_key"
      return 0
    fi
  done
  # If not in mapping, use the same relative path
  echo "${ES_DIR}/$en_rel"
}

# Source docs that must stay in the source language.
if [ -d "$EN_DIR" ]; then
  while IFS= read -r en_file; do
    rel="${en_file#"$EN_DIR"/}"
    es_file="$(find_source_file "$rel")"
    if [ ! -f "$es_file" ]; then
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
