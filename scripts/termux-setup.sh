#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v pkg >/dev/null 2>&1; then
  echo "Run this script inside Termux on Android."
  exit 1
fi
pkg update -y
pkg upgrade -y
pkg install -y nodejs-lts git curl
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example. Add your Discord bot and OAuth credentials before starting Kimi."
fi
npm install
node --version
echo
echo "Termux dependencies are ready."
echo "Edit .env, then run: bash scripts/termux-start.sh"
