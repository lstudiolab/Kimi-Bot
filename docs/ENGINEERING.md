# Kimi Engineering and Experience Standard

This document defines how Kimi is structured, how its runtime behaves, and how changes are reviewed. It is an implementation standard, not a claim that Kimi is affiliated with or built by Apple.

## Product principles

Kimi should feel deliberate, quiet, predictable, and dependable.

- **Clarity:** commands, settings, errors, and logs use specific language. Prefer a clear explanation over a short but ambiguous response.
- **Consistency:** the same interaction pattern behaves the same way across Foundation, Kimi Lock, Kimi Guard, Support, Verification, and installed plugins.
- **Feedback:** every user-initiated operation receives one acknowledgement, then a final result or a clear failure. Never send competing initial responses.
- **Safety:** default to least privilege, validate hierarchy and ownership at the point of action, and make destructive automation bounded and auditable.
- **Privacy:** do not log tokens, OAuth secrets, authorization headers, or unnecessary message content. Retention must be explicit and bounded.
- **Accessibility:** messages must remain understandable without relying on color, emoji, or visual decoration alone.

## Runtime architecture

Kimi is one application with clear internal boundaries. These boundaries organize code; they are not separate deployable products.

1. **Application composition** — loads configuration, constructs shared services, starts the dashboard, synchronizes global commands, and owns the Gateway lifecycle.
2. **Discord transport** — owns Gateway connection, heartbeats, reconnect/resume, REST requests, rate-limit handling, and Discord payload serialization.
3. **Interaction boundary** — acknowledges interactions once, routes commands and components, enforces authorization, and edits the original response for completion.
4. **Foundation** — provides shared configuration, persistence, localization, logging, analytics, and performance measurement.
5. **Domain systems** — implement moderation, security, verification, support, recovery, role selection, embeds, and automation using explicit service boundaries.
6. **Presentation** — produces consistent Discord messages and server-rendered dashboard pages. Presentation code must not own business rules.
7. **Storage** — owns schema compatibility, atomic persistence, bounded retention, per-server quotas, and migration from legacy records.

Domain systems must depend on narrow service interfaces where practical. Avoid circular dependencies, hidden global state, duplicate policy implementations, and direct filesystem access from feature handlers.

## Event and interaction lifecycle

Every Gateway event follows the same controlled path:

1. Decode and validate the event envelope.
2. Record a correlation identifier and receive timestamp.
3. Route to the owning domain service.
4. Check authorization, server configuration, and required Discord permissions.
5. Execute bounded work without blocking the Gateway receive loop.
6. Persist state changes atomically.
7. Emit a structured audit event with outcome and duration.
8. Return a concise user-facing result when the event originated from an interaction.

For Discord interactions, acknowledge before performing network or storage work that could exceed Discord's acknowledgement deadline. The acknowledgement is sent exactly once. Long-running work uses the original interaction response or a follow-up, never a second initial callback. Expired component tokens produce a recoverable message and a log entry, not an unhandled task failure.

## Swift implementation rules

- Use value types for immutable domain data and actors for mutable shared state.
- Keep actor-isolated work small. Do not hold an actor while performing unrelated network operations.
- Make asynchronous boundaries explicit with async and await; propagate cancellation.
- Use typed errors for expected failure cases. Do not silently convert all failures into success-shaped defaults.
- Validate external JSON at the boundary and avoid force unwraps for Discord-controlled values.
- Use descriptive names and Swift API design conventions. Optimize for clarity at the call site, not minimum character count.
- Document non-obvious invariants, security decisions, persistence behavior, and public APIs.
- Keep functions cohesive. Split files by domain responsibility when a file becomes difficult to reason about.
- Do not add dependencies without a concrete need and a maintenance rationale.

## Reliability and performance

- Set explicit network timeouts and bound retries.
- Retry rate-limited requests only after honoring Discord's retry delay.
- Retry transient server failures only for idempotent operations. Never blindly retry a message/channel creation request after an ambiguous 5xx response.
- Use exponential backoff with a cap and jitter for reconnect loops.
- Keep Gateway heartbeats independent from feature processing.
- Bound queues, caches, histories, message snapshots, transcript exports, and per-server storage.
- Prefer measured optimization. Record latency, error rate, retry count, memory pressure, and queue depth before changing algorithms.
- Avoid repeated expensive work in hot paths, including repeated serialization, full-history scans, and unnecessary Discord REST lookups.
- Preserve data with atomic writes. Publish in-memory state only after durable persistence succeeds.

## Security and moderation

- Enforce owner/staff permissions server-side; hiding a button is not authorization.
- Validate role permissions, role hierarchy, channel permissions, and bot capabilities immediately before privileged actions.
- Protect the server owner from automated sanctions and never allow the bot to punish itself.
- Use confidence thresholds and reversible containment before destructive actions when evidence is uncertain.
- Make every automatic action explainable: signal, policy, action, duration, and outcome.
- Apply per-user and per-server rate limits to interactive and automated operations.
- Treat message text, URLs, attachments, dashboard input, and imported app packages as untrusted.
- Keep secrets out of source control, logs, error messages, and dashboard HTML.

## Discord experience

- Use a restrained visual language: consistent neutral embed colors, concise titles, predictable field order, and meaningful timestamps.
- Prefer buttons and select menus for common actions; use modals for structured edits.
- Keep command names short, stable, and discoverable. Avoid duplicate commands for the same operation.
- Show the current state and the result of an action. Distinguish disabled, pending, completed, and failed states in text.
- Confirm destructive actions and make cancellation easy.
- Use ephemeral responses for private configuration feedback and public messages only when the result is intended for the channel.
- Do not use emoji as the only status indicator.

## Dashboard experience

- Keep navigation shallow and organize settings by task rather than by internal class or service name.
- Use progressive disclosure: show essential controls first and advanced policy details when requested.
- Explain the impact of a setting before enabling a destructive or high-impact behavior.
- Preserve user input after validation errors.
- Provide loading, empty, success, and failure states for every asynchronous view.
- Ensure layouts work on narrow mobile screens and remain usable with keyboard and assistive technology.
- Keep the dashboard server-rendered; browser JavaScript must not become a second business-logic runtime.

## Quality gates

A change is not complete because it compiles. Each change should include the smallest meaningful behavioral test and should pass:

```sh
swift build -c release
swift test
```

Before production rollout, validate on the actual Termux device and a disposable Discord server. The live test matrix must cover:

- Gateway connect, heartbeat timeout, reconnect, and resume.
- Global command registration and interaction acknowledgement under slow REST responses.
- Duplicate-click and expired-component behavior.
- Permission denial, missing permissions, role hierarchy, and owner protection.
- Moderation thresholds, false-positive handling, and audit records.
- Verification pass, review, reject, retry, and role assignment.
- Ticket open, concurrent open attempts, close confirmation, transcript export, and staff handoff.
- Automation matching, action failure, retry safety, and execution limits.
- Storage migration, interrupted writes, quota rejection, retention, and recovery.
- Dashboard authentication, session expiry, CSRF protection, and mobile layout.

A failed quality gate blocks release. Do not describe an untested change as production-ready.
