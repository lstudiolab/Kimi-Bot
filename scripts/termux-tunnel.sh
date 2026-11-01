#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared is not installed."
  echo "Install the Cloudflare cloudflared binary for your Android architecture, then run this script again."
  echo "Cloudflare docs: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/"
  exit 1
fi
echo "Exposing the local Kimi backend through a Cloudflare HTTPS tunnel."
echo "A Quick Tunnel URL is temporary. Configure its exact /auth/discord/callback URL in the Discord Developer Portal and .env."
exec cloudflared tunnel --url http://127.0.0.1:8787
