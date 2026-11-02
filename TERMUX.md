# Kimi Swift on Termux

A compatible Swift toolchain must be available for your Termux architecture. Swift availability varies by Termux repository and Android device.

```sh
pkg update && pkg upgrade
pkg install git swift
git clone https://github.com/lstudiolab/Kimi-Bot.git
cd Kimi-Bot
cp .env.example .env
```

Set `DISCORD_TOKEN` and `CLIENT_ID` in `.env`.

```sh
swift test
swift build -c release
swift run -c release
```

If `pkg install swift` is unavailable for your device, use a compatible Linux/Android Swift toolchain build. The iOS SDK/toolchain cannot simply be installed on Android.
