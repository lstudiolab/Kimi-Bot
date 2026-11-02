# Run Kimi with Swift on Android

Kimi's Discord bot and optional dashboard run in one Swift process. The dashboard is server-rendered and uses Discord OAuth2; there is no Node.js runtime.

## Install

```sh
pkg update -y
pkg upgrade -y
pkg install -y git swift tesseract zbar imagemagick
git clone https://github.com/lstudiolab/Kimi-Bot.git
cd Kimi-Bot
```

If your Termux repository does not provide a Swift package for your Android architecture, use an ARM64 Linux environment through `proot-distro` and install a compatible Swift toolchain there. The project is built and tested in Ubuntu Linux CI; native Android/Termux runtime validation is still required.

Optional image-analysis tools: Tesseract enables OCR, ZBar enables QR decoding, and ImageMagick enables perceptual duplicate matching. Kimi will still validate image signatures, metadata, and suspicious links if one of these tools is unavailable.\n\n## Configure the bot

```sh
cp .env.example .env
nano .env
```

Set `DISCORD_TOKEN` and `CLIENT_ID`. To enable the dashboard, configure an OAuth2 client secret and exact HTTPS redirect URI as described in [DASHBOARD.md](DASHBOARD.md). The dashboard listens on localhost port 8787 by default.

## Build and start

```sh
swift build -c release
swift test
swift run -c release
```

Or use `bash scripts/termux-start.sh`.

## HTTPS dashboard access

Keep the dashboard bound to `127.0.0.1`. Run the tunnel from a second Termux session:

```sh
cd ~/Kimi-Bot
bash scripts/termux-tunnel.sh
```

Use the public HTTPS hostname printed by the tunnel and register `https://YOUR_PUBLIC_HOST/oauth/callback` in Discord Developer Portal. Temporary tunnel hostnames change when recreated; use a named tunnel for a stable production URL.

Android battery optimization can stop long-running background processes. Exempt Termux from battery optimization and keep the device powered for continuous hosting.

## Data

Kimi stores its Swift runtime data in `data/timi.json`. Existing legacy fields are preserved in the same file while the Swift runtime stores its namespaced state under `_swift_runtime`. Back up the entire `data/` directory before upgrading. Never commit `.env` or production data.
