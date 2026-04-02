#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# Aveli Repo Index Builder (STABLE VERSION)
# ---------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INDEX_DIR="$ROOT/.repo_index"
SEARCH_MANIFEST="$INDEX_DIR/search_manifest.txt"
EXCLUDED_SEARCH_PATTERN='(^|/)\.env[^/]*$|(^|/)\.venv(/|$)|(^|/)__pycache__(/|$)|\.log$|(^|/)\.repo_index(/|$)|(^|/)node_modules(/|$)|(^|/)build(/|$)|(^|/)dist(/|$)|(^|/)coverage(/|$)|(^|/)target(/|$)'

echo "--------------------------------------------"
echo "Bygger repositorieindex"
echo "Reporot: $ROOT"
echo "Indexkatalog: $INDEX_DIR"
echo "--------------------------------------------"

# 🔥 Only clean index files (NOT vector DB)
mkdir -p "$INDEX_DIR"
cd "$ROOT"

rm -f \
  "$INDEX_DIR/files.txt" \
  "$INDEX_DIR/searchable_files.txt" \
  "$SEARCH_MANIFEST" \
  "$INDEX_DIR/tags" \
  "$INDEX_DIR/tree.txt" \
  "$INDEX_DIR/stats.txt"

# ---------------------------------------------------------
# File index
# ---------------------------------------------------------

echo "Indexerar filer..."

if command -v fd >/dev/null 2>&1; then
    fd --type f \
        --hidden \
        --exclude .git \
        --exclude node_modules \
        --exclude .venv \
        --exclude .repo_index \
        --exclude build \
        --exclude dist \
        --exclude target \
        --exclude coverage \
        . \
        > "$INDEX_DIR/files.txt"
else
    echo "fd hittades inte, använder find..."
    find . -type f \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -not -path "*/.venv/*" \
        -not -path "*/.repo_index/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        | sed 's#^\./##' \
        > "$INDEX_DIR/files.txt"
fi

# 🔥 sanity check
FILE_COUNT=$(wc -l < "$INDEX_DIR/files.txt")
echo "Indexerade filer: $FILE_COUNT"

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "FEL: Inga filer indexerades"
    exit 1
fi

# ---------------------------------------------------------
# Ripgrep searchable index
# ---------------------------------------------------------

echo "Genererar ripgrep-fillista..."

if ! command -v rg >/dev/null 2>&1; then
    echo "FEL: rg krävs för att bygga search_manifest.txt"
    exit 1
fi

rg --files \
    --hidden \
    --glob '!.git/*' \
    --glob '!node_modules/*' \
    --glob '!.venv/*' \
    --glob '!.repo_index/*' \
    | grep -Ev "$EXCLUDED_SEARCH_PATTERN" \
    | LC_ALL=C sort -u \
    > "$SEARCH_MANIFEST"

if [ ! -s "$SEARCH_MANIFEST" ]; then
    echo "FEL: search_manifest.txt skapades inte"
    exit 1
fi

if rg -n "$EXCLUDED_SEARCH_PATTERN" "$SEARCH_MANIFEST" >/dev/null 2>&1; then
    echo "FEL: search_manifest.txt innehåller exkluderade sökvägar"
    exit 1
fi

# ---------------------------------------------------------
# Symbol index (functions, classes etc)
# ---------------------------------------------------------

echo "Genererar symbolindex..."

if command -v ctags >/dev/null 2>&1; then
    ctags -R \
        --exclude=.git \
        --exclude=node_modules \
        --exclude=.venv \
        --exclude=.repo_index \
        --exclude=build \
        --exclude=dist \
        --exclude=target \
        -f "$INDEX_DIR/tags" \
        "$ROOT" 2>/dev/null || true
else
    echo "ctags är inte installerat, hoppar över symbolindex"
fi

# ---------------------------------------------------------
# Directory tree
# ---------------------------------------------------------

echo "Genererar katalogträd..."

if command -v tree >/dev/null 2>&1; then
    tree -a \
        -I ".git|node_modules|.venv|.repo_index|build|dist|coverage" \
        "$ROOT" \
        > "$INDEX_DIR/tree.txt"
else
    echo "tree är inte installerat, använder find för katalogträd..."
    find "$ROOT" -type d \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -not -path "*/.repo_index/*" \
        > "$INDEX_DIR/tree.txt"
fi

# ---------------------------------------------------------
# Repo statistics
# ---------------------------------------------------------

echo "Genererar repostatistik..."

{
echo "Repostatistik"
echo "============="
echo ""
echo "Totalt antal filer:"
wc -l "$INDEX_DIR/files.txt"
echo ""
echo "Vanligaste filtyper:"
cut -d. -f2 "$INDEX_DIR/files.txt" | sort | uniq -c | sort -nr | head -20
echo ""
echo "Största kataloger:"
du -h --max-depth=2 "$ROOT" 2>/dev/null | sort -hr | head -20
} > "$INDEX_DIR/stats.txt"

# ---------------------------------------------------------
# Done
# ---------------------------------------------------------

echo ""
echo "Repositorieindex byggdes klart."
echo ""
echo "Filer:"
echo "  files.txt            ($FILE_COUNT poster)"
echo "  search_manifest.txt"
echo "  tags"
echo "  tree.txt"
echo "  stats.txt"
echo ""
