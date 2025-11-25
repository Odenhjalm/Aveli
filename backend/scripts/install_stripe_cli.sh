#!/usr/bin/env bash
set -euo pipefail

# Simple helper to install the Stripe CLI locally.
# Usage: ./scripts/install_stripe_cli.sh [install_dir]
# Defaults to ~/.local/bin

INSTALL_DIR="${1:-$HOME/.local/bin}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$INSTALL_DIR"

ARCHIVE_URL="https://cli.stripe.com/download/linux_x86_64"
ARCHIVE_PATH="$TMP_DIR/stripe.tar.gz"

curl -fsSL "$ARCHIVE_URL" -o "$ARCHIVE_PATH"
tar -xzf "$ARCHIVE_PATH" -C "$TMP_DIR"

mv "$TMP_DIR/stripe" "$INSTALL_DIR/stripe"
chmod +x "$INSTALL_DIR/stripe"

echo "Stripe CLI installerad till $INSTALL_DIR/stripe"
echo "Lägg till katalogen i din PATH om den inte redan är det."
