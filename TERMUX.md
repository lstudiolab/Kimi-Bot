# Run Kimi with Swift on Android

Kimi runs as a Discord-only Swift bot. It does not start a website, dashboard, OAuth callback, or tunnel.

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

Set only `DISCORD_TOKEN` and `CLIENT_ID`. All server setup and configuration are performed through Discord slash commands and interactive components.

## Build and start

```sh
swift build -c release
swift test
swift run -c release
```

Or use `bash scripts/termux-start.sh`.

## Data

Kimi stores its Swift runtime data in `data/timi.json`. Existing legacy fields are preserved in the same file while the Swift runtime stores its namespaced state under `_swift_runtime`. Back up the entire `data/` directory before upgrading. Never commit `.env` or production data.
