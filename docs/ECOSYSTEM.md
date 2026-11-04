# Kimi plugins

Kimi is organized around six first-party plugins. The **Plugin Store** is the owner-facing place to add or remove them. Existing installation records remain compatible.

- **Welcome** — welcome and departure messages.
- **Auto Role** — automatic assignment of one configured role to new members.
- **Role Picker** — self-service role selection menus.
- **Embeds** — create, edit and publish reusable server embeds.
- **Kimi Lock** — anti-spam, AutoMod, raid and join protection, anti-nuke containment, verification, sanctions, security review, and recovery.
- **Support** — private tickets, staff handoff, priority, transcripts, and support activity.

Plugins are installed per server. Each plugin owns one focused system, except Kimi Lock which groups security and moderation controls. Shared private-channel setup is a core Kimi service, not an installable plugin. Systems can be enabled or disabled independently, and removing a plugin preserves its saved configuration. The shared runtime uses a bounded background queue for non-critical work, in-flight task deduplication, backpressure, and a short-lived LRU cache for permission diagnostics. Enforcement remains synchronous where delay could increase harm.

The Plugin Store currently presents Kimi's built-in plugins. Downloaded third-party package code is not activated by the runtime; package validation and installation remain separate from plugin activation.

## Kimi Guard activity control

Kimi Guard uses independent per-server token buckets for member activity, third-party bot messages, and Kimi's own automation triggers.

- Members receive 10 action tokens. Each message or Discord interaction consumes one token; one token returns every 2 seconds, up to the 10-token capacity.
- Other bots receive a separate 10-token bucket. Only messages authored by that bot consume its tokens; another member mentioning a bot cannot drain its bucket or trigger quarantine. Regeneration starts only after that bot has been quiet for 2 seconds; continued messages keep moving the quiet window.
- When a member exhausts all 10 tokens, Kimi locks their actions until the full 10-token bucket has regenerated (up to 20 seconds from an empty bucket). Interactions receive an ephemeral cooldown notice. Ordinary messages that exceed the member bucket are deleted because Discord does not support ephemeral replies to normal messages.
- When a third-party bot exhausts its bucket, Kimi records an incident, removes roles it can safely manage, and attempts a 28-day timeout. Discord may reject timeouts for bot accounts, so role removal is the primary restriction.
- Only the server owner can use `/guard-review` to restore the bot's saved roles or keep it restricted. New-bot approval and rejection controls are also owner-only and are posted only in a private owner channel. Approval is blocked while a bot has Administrator permission because Discord lets Administrator bypass channel overwrites. During approval, temporary denies are removed only from channels visible to @everyone; private-channel denies remain in place. Kimi cannot review or restrict its own account.
- Kimi's own automation triggers use the bot-style quiet-window bucket. Critical Kimi Lock security and recovery handlers are not paused by automation backpressure.
- Rate state is persisted, inactive buckets expire after seven days, and the data is included in each server's storage quota.

## Security hardening

The current security controls also enforce the following boundaries:

- Dashboard write requests require a same-origin browser request. Login throttling uses the direct socket peer address rather than trusting client-supplied forwarding headers, and active Discord permissions are refreshed before dashboard access is granted.
- Self-service role menus are bound to the exact Kimi-authored message and channel. Roles are revalidated against current permissions and hierarchy at assignment time; newly unsafe roles are not granted, and previously selected roles are removable when Kimi can manage them.
- Ticket open buttons must belong to a currently published Kimi panel. Ticket priority controls must originate from the real ticket message inside the ticket channel; copied or forged controls are rejected.
- Verification buttons are bound to the exact prompt Kimi sent to that member. Review decisions are bound to a single pending review message, so an old rejection button cannot be replayed after the member rejoins. Bot approval controls require a private Kimi channel and the server owner.
- Automation messages suppress role and everyone mentions. Automation role changes re-fetch the target member and role, and timeouts skip bots, the server owner, and privileged moderators. Malformed saved automation actions fail closed.
- Automatic anti-spam sanctions re-check the target immediately before enforcement and skip bots, the owner, and privileged moderators.
- Channel recovery requires a recent matching audit-log event and validates saved channel types, overwrite counts, IDs, and permission bitfields before recreating a channel.
- Webhook messages use bot-style activity limits. When a webhook exhausts its bucket, Kimi deletes subsequent messages and privately alerts the owner; Kimi does not silently delete or disable the webhook integration.

These controls reduce abuse paths but do not replace Discord permission hygiene. Kimi cannot override role hierarchy, server ownership, missing permissions, or Discord API restrictions. Review bot permissions and remove integrations you do not trust.
