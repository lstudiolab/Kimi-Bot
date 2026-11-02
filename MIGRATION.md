# Swift migration status

All backend runtime code is now organized as Swift Package Manager sources. The former Node/npm backend and browser JavaScript bundles have been removed from the active tree. The original JavaScript source remains available in Git history for parity reference.

## Swift modules present
- Configuration, logging, persistent storage and legacy data preservation
- Discord REST client and Gateway websocket transport
- Global and per-guild slash-command catalog
- App registry and per-server app installation state
- Foundation welcome/goodbye and automatic role assignment
- Kimi Lock moderation policy, verification records/review, audit monitoring and security audit
- Support ticket records, private ticket channels, panel, close confirmation and transcript capture
- Role Picker select menu and safe-role filtering
- Embed validation, persistence and publishing
- Automation rule persistence
- Recovery message/channel snapshots with seven-day and storage caps
- Server-rendered dashboard with Discord OAuth and form-based app management
- Termux scripts and Swift CI

## Remaining parity work
The original system had substantially more behavior than the current Swift implementation. The following still require implementation and validation before production replacement:
- Full anti-nuke containment and owner review workflow, raid heuristics, timed sanction scheduler and complete AutoMod integration
- Full role-picker editing, multiple menus, per-menu role removal policy and hierarchy revalidation
- Full embed modal editor, field/thumbnail/image/author/footer editing and placement management
- Complete Support staff handoff, priorities, attachment export, paginated transcripts and access controls
- Complete verification panel management, role hierarchy checks, reviewer permissions and audit UI
- Automation builder, trigger conditions, action execution, retry policy and execution history
- Channel/message recovery restoration, audit attribution, attachment backup and snapshot integrity
- Dashboard analytics, activity logs, command/system toggles, language preferences and all prior account-link flows
- Complete legacy data-schema migration for every prior Kimi subsystem

## Safety and rollout
The Swift runtime is not yet feature-equivalent to the previous JavaScript implementation. Do not remove or overwrite production data. Preserve `data/timi.json` and the backup before first launch. Run `swift build -c release` and `swift test`, then validate all Discord permissions, component interactions and Android/Termux networking before using it as the live bot.
