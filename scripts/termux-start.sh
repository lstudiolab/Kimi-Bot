#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f .env ]; then
  echo "Missing .env. Run: bash scripts/termux-setup.sh"
  exit 1
fi
if ! grep -Eq '^DISCORD_TOKEN=.+$' .env || ! grep -Eq '^CLIENT_ID=[0-9]{15,22}$' .env; then
  echo "Set DISCORD_TOKEN and CLIENT_ID in .env before starting Kimi."
  exit 1
fi
if ! grep -Eq '^DISCORD_OAUTH_CLIENT_SECRET=.+$' .env || ! grep -Eq '^DISCORD_OAUTH_REDIRECT_URI=https://.+' .env; then
  echo "Discord dashboard login is not configured. Set DISCORD_OAUTH_CLIENT_SECRET and the public HTTPS callback URL in .env."
  exit 1
fi
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || true
fi
npm run check
exec npm start
