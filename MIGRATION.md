# Kimi Swift migration

The Swift rewrite is being performed on the `migration/swift-rewrite` branch. The existing `main` branch remains unchanged while the replacement is built and validated.

## Target

- Swift is the only application/runtime language.
- Discord Gateway and REST integration use DiscordBM.
- Swift Package Manager owns dependencies and builds.
- Foundation, Kimi Lock, Support, and shared services remain separate modules.
- Persistent guild data is migrated without changing its JSON schema where possible.
- Dashboard and operational tooling are included in the migration scope; they are not considered complete merely because the bot process compiles.

## Current migration checkpoint

- Swift package and executable entry point added.
- Environment configuration and structured logging ported.
- JSON-compatible storage foundation added.
- App registry and app install/uninstall state management ported.
- Component routing, permission policy, storage quota and text utilities ported.
- Discord Gateway connection scaffold added.

## Not yet migrated

The Discord command catalogue and handlers, all Foundation/Kimi Lock/Support system behavior, automation execution, dashboard API and browser interface, auth/session handling, image analysis, recovery, tests and deployment scripts still require porting and parity tests. The JavaScript implementation must not be removed until those replacements are implemented and verified.
