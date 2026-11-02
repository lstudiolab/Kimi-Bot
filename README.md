# Kimi

Kimi is a modular Discord server platform. Its bot runtime and server-rendered dashboard are written in Swift.

## Requirements
- Swift 5.9 or later
- Discord bot token and application ID
- Optional Discord OAuth2 client secret and public HTTPS callback for dashboard sign-in

## Configure
Copy `.env.example` to `.env`. Set `DISCORD_TOKEN` and `CLIENT_ID`. For dashboard sign-in, configure Discord OAuth2 and set `DISCORD_OAUTH_CLIENT_SECRET` and `DISCORD_OAUTH_REDIRECT_URI`.

## Build and run
```sh
swift build -c release
swift test
swift run -c release
```

Kimi listens for Discord Gateway events and serves its optional dashboard on `127.0.0.1:8787`. Keep the dashboard behind an HTTPS tunnel or reverse proxy. See [TERMUX.md](TERMUX.md), [DASHBOARD.md](DASHBOARD.md), and [MIGRATION.md](MIGRATION.md).

The migration is ongoing. Do not replace a working production instance until the remaining feature parity and Termux validation items in MIGRATION.md are complete.
