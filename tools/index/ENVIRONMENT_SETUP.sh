#!/usr/bin/env bash
set -e

echo "[SETUP] Ensuring clean search environment..."

if [ ! -d ".repo_index/.search_venv" ]; then
  python3 -m venv .repo_index/.search_venv
fi

source .repo_index/.search_venv/bin/activate

echo "[SETUP] Upgrading pip..."
pip install --upgrade pip

echo "[SETUP] Installing CUDA PyTorch..."
pip install --force-reinstall \
  torch torchvision torchaudio \
  --index-url https://download.pytorch.org/whl/cu128

echo "[SETUP] Installing index dependencies..."
pip install -r tools/index/requirements.txt

echo "[SETUP] Verifying CUDA..."

python - << 'EOF'
import torch
print("cuda:", torch.version.cuda)
print("available:", torch.cuda.is_available())
print("device:", torch.cuda.get_device_name(0) if torch.cuda.is_available() else "none")
if not torch.cuda.is_available():
    raise SystemExit("CUDA NOT AVAILABLE — STOP")
EOF

echo "[SETUP] Environment ready."