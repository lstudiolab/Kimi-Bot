# Kimi — Swift

Kimi is a modular Discord bot with a Swift runtime and Swift Package Manager build.

## Requirements
- Swift 5.9+
- Discord bot token
- Discord application ID

## Configure
Copy `.env.example` to `.env`, then set `DISCORD_TOKEN` and `CLIENT_ID`.

## Run
```sh
swift test
swift run -c release
```

Persistent data is stored under `data/`. Back up the existing data directory before migrating. Legacy Node data is not automatically transformed in full.

## Swift modules
- Configuration, logging, JSON storage and quota.
- Discord Gateway and REST runtime.
- Per-server app installation registry.
- Foundation setup primitives.
- Kimi Lock rate detection, policy persistence and verification scoring.
- Support ticket persistence.
- Automation rule persistence.
- Protection, embed validation and role-picker safety.

See `MIGRATION.md` for known feature-parity gaps and production readiness.
