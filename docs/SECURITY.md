# Kimi Lock security model

Kimi Lock uses deterministic checks and Discord's server-side audit events. It does not execute user-supplied files, inspect private user-token activity, or send message contents to a third-party moderation service.

## Active protections

- Text normalization removes zero-width and formatting controls, folds diacritics and common Cyrillic lookalikes, and normalizes common leetspeak before checking custom blocked phrases.
- Built-in profanity checks and per-server blocked phrases run on message content. Configure custom slurs and server-specific terms from `/kimi-lock-screen`.
- Message checks cover excessive capitals, formatting floods, message length, high message rates, repeated identical bursts, emoji/custom-emote volume, stickers, Discord invites, mass mentions, suspicious URL patterns, and executable/script attachment names and MIME types.
- Message edits are checked again; a message cannot become a malicious link or blocked phrase merely by being edited after posting.
- High-confidence malicious URL and executable-attachment findings contribute to a local cross-server user reputation record. Reputation increases review severity; it does not independently cause a ban.
- Reaction bursts are rate-limited per user and target message. Thread creation bursts are deleted and escalated. Ticket creation has a per-user cooldown and a per-server open-queue ceiling.
- Voice-channel hopping and repeated soundboard effects are monitored. These checks do not inspect voice audio.
- Profile-name checks cover usernames and server nicknames for configured blocked terms and common staff/service impersonation patterns. Violating server nicknames are cleared when Kimi has permission.
- Audit-log monitoring watches destructive channel, role, permission-overwrite, member-removal, and webhook actions. Repeated high-risk actions trigger Kimi Guard containment.
- Recovery snapshots existing channels and roles at startup and captures subsequent changes. Deleted channels are restored from snapshots. Deleted roles are recreated with elevated permission bits stripped.
- Moderation and audit event windows are held by shared runtime services or persisted records, rather than being reset for each incoming event.

## Configuration

Each installed plugin exposes one configuration command:

- `/kimi-lock-screen`
- `/ticket-screen`
- `/welcome-screen`
- `/auto-role-screen`
- `/role-picker-screen`
- `/embeds-screen`

Kimi Lock's screen controls enable/disable protection, choose sanctions and rate limits, set timeout duration, and edit blocked keywords. Ticket, Welcome, Auto Role, Role Picker and Embeds screens expose their current settings and interactive selectors/editors.

## Discord permissions and gateway intents

Kimi requires the relevant Discord permissions to delete messages, timeout members, manage channels/roles, manage webhooks, read audit logs, and restore snapshots. Discord's role hierarchy still applies; Kimi cannot modify roles above its highest role or bypass an owner's Administrator permission.

The Gateway requests Guild Members and Message Content privileged intents, plus guild messages, reactions, voice states and webhooks. Enable the privileged intents in the Discord Developer Portal for the bot application. Without Message Content, content-based filters cannot reliably inspect messages. Without Guild Members, join and profile-change monitoring is incomplete.

## Platform limitations (not claims of protection)

- The verification flow does not automatically quarantine a new member from every channel. For actual room isolation, deny `View Channel` to `@everyone` on restricted categories/channels and grant it to the verified role. The bot's verification role assignment then controls access; otherwise an unverified member may still see channels permitted to `@everyone`.
- Discord does not expose the contents of voice audio to ordinary bots. Kimi can monitor voice-state changes and soundboard effect events, but cannot detect microphone audio blasting or judge spoken audio.
- Discord does not expose arbitrary members' profile bios to bots. Presence/status visibility requires the privileged Presence intent and still does not provide profile bios. This implementation does not claim to moderate bios or all custom statuses.
- A bot cannot observe DMs exchanged between two other users. It can only inspect messages sent to the bot itself.
- User-token/self-bot execution cannot be proven from Gateway events. Kimi detects behavior patterns such as abnormal message bursts and suspicious join activity, not the use of a particular token or script.
- Attachment checks use Discord-provided filenames and MIME metadata. They do not download and execute files, perform antivirus scanning, or inspect every file's bytes.
- URL checks use structural heuristics and a local list of known tracking domains. They are not a live global phishing feed and cannot guarantee detection of newly registered malicious domains.
- Avatar cloning requires image comparison and identity context that this implementation does not yet perform.
- Cross-server reputation is local to this Kimi installation. It is not a distributed threat-intelligence network shared between independent bot deployments.
- Discord audit-log delivery and permission hierarchy limit how quickly Kimi can contain an administrator. The server owner and members with permissions above Kimi's role remain outside Kimi's ability to override.

These boundaries are intentional: Kimi must not claim that it can inspect data Discord does not provide or guarantee prevention where the platform does not grant the required authority.
