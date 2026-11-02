# Kimi ecosystem

Kimi is organized around three owner-facing plugins. Legacy names normalize to canonical names so existing installations remain usable.

- **Kimi Lock** — anti-spam, AutoMod, raid and join protection, anti-nuke containment, verification, sanctions, security review, and recovery.
- **Support** — private tickets, staff handoff, priority, transcripts, and support activity.
- **Foundation** — guided setup, welcome flows, automatic roles, role menus, and reusable embeds.

The shared runtime uses a bounded background queue for expensive non-critical work, in-flight task deduplication, backpressure, and a short-lived LRU cache for permission diagnostics. Enforcement remains synchronous where delay could increase harm. Each plugin exposes diagnostics helpers for setup flows. Configuration is preserved when a plugin is disabled.