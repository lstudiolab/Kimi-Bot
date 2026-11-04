# Kimi

Kimi is a Discord-native server platform. Configuration and moderation are performed through Discord slash commands and interactive components.

## Requirements
- Swift 5.9 or later
- Discord bot token and application ID

## Configure
Copy `.env.example` to `.env`. Set `DISCORD_TOKEN` and `CLIENT_ID`. No website, OAuth client secret, public callback, or tunnel is required.

## Build and run
```sh
swift build -c release
swift test
swift run -c release
```

Kimi connects directly to the Discord Gateway and Discord REST API. All setup and configuration are completed inside Discord. See [TERMUX.md](TERMUX.md) and [MIGRATION.md](MIGRATION.md).

The migration is ongoing. Do not replace a working production instance until the remaining feature parity and Termux validation items in MIGRATION.md are complete.

## Project layout

- `Sources/Kimi/App` — application entry point and lifecycle.
- `Sources/Kimi/Platform/Discord` — Discord Gateway, REST, commands, components, and interaction adapters.
- `Sources/Kimi/Features` — domain features grouped by responsibility.
- `Sources/Kimi/Services` — plugin and platform services.
- `Sources/Kimi/Infrastructure` — persistence and platform support.
- `Sources/Kimi/Resources` — localization and bundled text resources.
- `Tests/KimiTests` — automated tests.
- `docs` and the root guides — engineering and operator documentation.

All Swift files remain in the same SwiftPM target. This is a source-tree organization change; it does not introduce new runtime modules or alter feature behavior.

## Engineering standard

See [docs/ENGINEERING.md](docs/ENGINEERING.md) for Kimi's Swift architecture, runtime lifecycle, security requirements, Discord interaction conventions, and release quality gates.
