# Kimi apps

Kimi is organized around three first-party apps. The **App Store** is the owner-facing place to add or remove them. Older plugin names and saved installation records remain supported for compatibility.

- **Foundation** — guided setup, welcome flows, automatic roles, role menus, and reusable embeds.
- **Kimi Lock** — anti-spam, AutoMod, raid and join protection, anti-nuke containment, verification, sanctions, security review, and recovery.
- **Support** — private tickets, staff handoff, priority, transcripts, and support activity.

Apps are installed per server. Their systems can be enabled or disabled independently, and removing an app preserves its saved configuration. The shared runtime uses a bounded background queue for non-critical work, in-flight task deduplication, backpressure, and a short-lived LRU cache for permission diagnostics. Enforcement remains synchronous where delay could increase harm.

The App Store currently presents Kimi's built-in apps. Downloaded third-party package code is not activated by the runtime; package validation and installation remain separate from app activation.

## Kimi Guard activity control

Kimi Guard uses independent per-server token buckets for member activity, third-party bot messages, and Kimi's own automation triggers.

- Members receive 10 action tokens. Each message or Discord interaction consumes one token; one token returns every 2 seconds, up to the 10-token capacity.
- Other bots receive a separate 10-token bucket. Only messages authored by that bot consume its tokens; another member mentioning a bot cannot drain its bucket or trigger quarantine. Regeneration starts only after that bot has been quiet for 2 seconds; continued messages keep moving the quiet window.
- When a member exhausts all 10 tokens, Kimi locks their actions until the full 10-token bucket has regenerated (up to 20 seconds from an empty bucket). Interactions receive an ephemeral cooldown notice. Ordinary messages that exceed the member bucket are deleted because Discord does not support ephemeral replies to normal messages.
- When a third-party bot exhausts its bucket, Kimi records an incident, removes roles it can safely manage, and attempts a 28-day timeout. Discord may reject timeouts for bot accounts, so role removal is the primary restriction.
- Only the server owner can use `/guard-review` to restore the bot's saved roles or keep it restricted. New-bot approval and rejection controls are also owner-only and are posted only in a private owner channel. Approval is blocked while a bot has Administrator permission because Discord lets Administrator bypass channel overwrites. During approval, temporary denies are removed only from channels visible to @everyone; private-channel denies remain in place. Kimi cannot review or restrict its own account.
- Kimi's own automation triggers use the bot-style quiet-window bucket. Critical Kimi Lock security and recovery handlers are not paused by automation backpressure.
- Rate state is persisted, inactive buckets expire after seven days, and the data is included in each server's storage quota.
