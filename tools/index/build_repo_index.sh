#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------
# Aveli Repo Index Builder
# ---------------------------------------------------------
# Generates a lightweight repository index to help AI agents
# and developers quickly navigate the codebase.
#
# Output directory (ignored by git):
#   .repo_index/
#
# Generated files:
#   files.txt      → list of all source files
#   tags           → symbol index (functions, classes etc)
#   tree.txt       → directory structure
#   stats.txt      → repo statistics
#
# Safe to commit this script to the repo.
# The generated index directory should stay in .gitignore.
# ---------------------------------------------------------

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
INDEX_DIR="$ROOT/.repo_index"

echo "--------------------------------------------"
echo "Building repository index"
echo "Repo root: $ROOT"
echo "Index dir: $INDEX_DIR"
echo "--------------------------------------------"

rm -rf "$INDEX_DIR"
mkdir -p "$INDEX_DIR"

# ---------------------------------------------------------
# File index
# ---------------------------------------------------------

echo "Indexing files..."

if command -v fd >/dev/null 2>&1; then
    fd --type f \
        --exclude .git \
        --exclude node_modules \
        --exclude .venv \
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
        -not -path "*/build/*" \
        -not -path "*/dist/*" \
        > "$INDEX_DIR/files.txt"
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
        -I ".git|node_modules|.venv|build|dist|coverage" \
        "$ROOT" \
        > "$INDEX_DIR/tree.txt"
else
    echo "tree not installed, generating fallback tree..."
    find "$ROOT" -type d \
        -not -path "*/.git/*" \
        -not -path "*/node_modules/*" \
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
echo "Location:"
echo "  $INDEX_DIR"
echo ""
echo "Files generated:"
echo "  files.txt"
echo "  searchable_files.txt"
echo "  tags"
echo "  tree.txt"
echo "  stats.txt"
echo ""