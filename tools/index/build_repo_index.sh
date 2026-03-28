#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# Aveli Repo Index Builder (STABLE VERSION)
# ---------------------------------------------------------

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
INDEX_DIR="$ROOT/.repo_index"

echo "--------------------------------------------"
echo "Building repository index"
echo "Repo root: $ROOT"
echo "Index dir: $INDEX_DIR"
echo "--------------------------------------------"

# 🔥 Only clean index files (NOT vector DB)
mkdir -p "$INDEX_DIR"

rm -f \
  "$INDEX_DIR/files.txt" \
  "$INDEX_DIR/searchable_files.txt" \
  "$INDEX_DIR/tags" \
  "$INDEX_DIR/tree.txt" \
  "$INDEX_DIR/stats.txt"

# ---------------------------------------------------------
# File index
# ---------------------------------------------------------

echo "Indexing files..."

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
        > "$INDEX_DIR/files.txt"
else
    echo "fd not found, using find..."
    find "$ROOT" -type f \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -not -path "*/.venv/*" \
        -not -path "*/.repo_index/*" \
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        > "$INDEX_DIR/files.txt"
fi

# 🔥 sanity check
FILE_COUNT=$(wc -l < "$INDEX_DIR/files.txt")
echo "Indexed files: $FILE_COUNT"

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "ERROR: No files indexed"
    exit 1
fi

# ---------------------------------------------------------
# Ripgrep searchable index
# ---------------------------------------------------------

echo "Generating ripgrep file list..."

if command -v rg >/dev/null 2>&1; then
    rg --files \
        --hidden \
        --glob '!.git/*' \
        --glob '!node_modules/*' \
        --glob '!.venv/*' \
        --glob '!.repo_index/*' \
        > "$INDEX_DIR/searchable_files.txt"
fi

# ---------------------------------------------------------
# Symbol index (functions, classes etc)
# ---------------------------------------------------------

echo "Generating symbol index..."

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
    echo "ctags not installed, skipping symbol index"
fi

# ---------------------------------------------------------
# Directory tree
# ---------------------------------------------------------

echo "Generating directory tree..."

if command -v tree >/dev/null 2>&1; then
    tree -a \
        -I ".git|node_modules|.venv|.repo_index|build|dist|coverage" \
        "$ROOT" \
        > "$INDEX_DIR/tree.txt"
else
    echo "tree not installed, fallback tree..."
    find "$ROOT" -type d \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
        -not -path "*/.repo_index/*" \
        > "$INDEX_DIR/tree.txt"
fi

# ---------------------------------------------------------
# Repo statistics
# ---------------------------------------------------------

echo "Generating repo stats..."

{
echo "Repo statistics"
echo "==============="
echo ""
echo "Total files:"
wc -l "$INDEX_DIR/files.txt"
echo ""
echo "Top file types:"
cut -d. -f2 "$INDEX_DIR/files.txt" | sort | uniq -c | sort -nr | head -20
echo ""
echo "Largest directories:"
du -h --max-depth=2 "$ROOT" 2>/dev/null | sort -hr | head -20
} > "$INDEX_DIR/stats.txt"

# ---------------------------------------------------------
# Done
# ---------------------------------------------------------

echo ""
echo "Repository index built successfully."
echo ""
echo "Files:"
echo "  files.txt            ($FILE_COUNT entries)"
echo "  searchable_files.txt"
echo "  tags"
echo "  tree.txt"
echo "  stats.txt"
echo ""