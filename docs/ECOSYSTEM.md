# Kimi apps

Kimi is organized around three first-party apps. The **App Store** is the owner-facing place to add or remove them. Older plugin names and saved installation records remain supported for compatibility.

- **Foundation** — guided setup, welcome flows, automatic roles, role menus, and reusable embeds.
- **Kimi Lock** — anti-spam, AutoMod, raid and join protection, anti-nuke containment, verification, sanctions, security review, and recovery.
- **Support** — private tickets, staff handoff, priority, transcripts, and support activity.

Apps are installed per server. Their systems can be enabled or disabled independently, and removing an app preserves its saved configuration. The shared runtime uses a bounded background queue for non-critical work, in-flight task deduplication, backpressure, and a short-lived LRU cache for permission diagnostics. Enforcement remains synchronous where delay could increase harm.

The App Store currently presents Kimi's built-in apps. Downloaded third-party package code is not activated by the runtime; package validation and installation remain separate from app activation.
