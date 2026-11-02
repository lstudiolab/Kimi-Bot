# Kimi — Swift

Kimi's Discord runtime is being migrated to Swift for Termux/Linux. The runtime uses Swift Package Manager and Foundation networking.

## Configure
Copy `.env.example` to `.env`; set `DISCORD_TOKEN` and `CLIENT_ID`.

## Run
```sh
swift build -c release
swift run -c release
```

Keep a backup of the existing `data/` directory before changing runtime versions. See MIGRATION.md for feature parity and limitations.
