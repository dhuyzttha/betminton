#!/bin/bash
set -e

# ==============================================================================
# Badminton Hawk-Eye Pro - Python Computer Vision Engine Launcher
# ==============================================================================

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$PROJECT_DIR/backend"
cd "$BACKEND_DIR"

echo "================================================================="
echo "   BADMINTON HAWK-EYE PRO: COMPUTER VISION SERVER & ENGINE       "
echo "================================================================="

# Check Python3
if ! command -v python3 &> /dev/null; then
    echo "[-] Python3 is required but not installed."
    exit 1
fi

echo "[+] Python version: $(python3 --version)"

# Check virtual environment or dependencies
echo "[+] Starting FastAPI Server on port 8000..."
python3 -m uvicorn server:app --host 0.0.0.0 --port 8000 --reload
