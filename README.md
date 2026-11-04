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

## Project layout

- `Sources/Kimi/App` — application entry point and lifecycle.
- `Sources/Kimi/Platform/Discord` — Discord Gateway, REST, commands, components, and interaction adapters.
- `Sources/Kimi/Features` — domain features grouped by responsibility.
- `Sources/Kimi/Services` — dashboard and plugin services.
- `Sources/Kimi/Infrastructure` — persistence and platform support.
- `Sources/Kimi/Resources` — localization and bundled text resources.
- `Tests/KimiTests` — automated tests.
- `docs` and the root guides — engineering and operator documentation.

All Swift files remain in the same SwiftPM target. This is a source-tree organization change; it does not introduce new runtime modules or alter feature behavior.

## Engineering standard

See [docs/ENGINEERING.md](docs/ENGINEERING.md) for Kimi's Swift architecture, runtime lifecycle, security requirements, Discord interaction conventions, dashboard experience, and release quality gates.
