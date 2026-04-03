#!/usr/bin/env bash
set -euo pipefail

trap "echo '🛑 Shutting down...'; pkill -P $$ || true" EXIT

DEV_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DEV_SCRIPT_DIR="$(cd "$(dirname "$DEV_SCRIPT_PATH")" && pwd)"

echo "🚀 Starting Aveli dev environment..."

# 🟢 Ensure DB is running
"$DEV_SCRIPT_DIR/ensure_db.sh"

# 🟢 Start backend
echo "🔧 Starting backend..."
"$DEV_SCRIPT_DIR/start_backend.sh" &

# 🟢 Start MCP servers
echo "🧠 Starting MCP servers..."

python tools/mcp/semantic_search_server.py &
python tools/mcp/logs_server.py &
python tools/mcp/media_control_plane.py &

# 🟢 Keep process alive
wait