# Kimi Swift migration

The active `main` branch is now a Swift Package Manager application. The previous Node/npm runtime, browser JavaScript bundles, and JavaScript test suite are no longer part of the active tree. The original implementation remains in Git history as the behavior reference. HTML and CSS remain only as static web presentation assets; dashboard behavior is served by Swift and does not depend on browser JavaScript.

## Ported runtime and subsystems

- Discord REST and Gateway runtime, slash-command registration, component routing, interaction acknowledgement, and structured logging.
- Configuration, persistent namespaced storage, legacy `data/timi.json` reads, storage quota tracking, app registry, library package management, and per-server app installation.
- Foundation welcome/goodbye messages and automatic role assignment.
- Kimi Lock AutoMod rules for rate limits, blocked phrases, invite links, mass mentions, excessive capitals, and oversized messages; configurable delete, timeout, kick, or ban sanctions; per-channel/member rate tracking; moderation logs.
- Kimi Guard audit thresholds, privileged-role containment, owner review, new-bot approval controls, and join-burst detection with temporary containment for very new accounts.
- Verification attempt history, account-age/avatar/risk scoring, pass/review/reject thresholds, manual owner review, required-role gate, and verified-role hierarchy validation.
- Support private ticket channels, opener/staff permissions, named priority levels, close confirmation, staff handoff threads, paginated transcript collection, attachment-link retention, and archive-channel export.
- Multiple named Role Picker menus with safe-role filtering, live Manage Roles and hierarchy checks, and per-menu member selections.
- Saved embeds with title, description, author, footer, thumbnail, image, title URL, and fields; validation and publishing.
- Automation CRUD, enable/disable, message-content conditions, member/message triggers, send/delete/timeout/add-role/remove-role actions, and bounded execution history.
- Message and channel snapshots, user-deletion recovery, bulk-delete recovery, channel restoration, seven-day retention, and a 4 MB message-content budget.
- Image signature/dimension checks, Discord attachment validation, suspicious-link heuristics, and security reporting.
- Discord OAuth dashboard with server-rendered pages, app management, welcome and moderation settings, language selection, activity summaries, recent logs, and command inventory.
- Localization catalog, analytics counters, performance sampling, and Termux shell setup/start scripts.

## Known parity and deployment gaps

The migration is not considered production-equivalent until these items are closed and tested against the original behavior:

- Image inspection currently validates image signatures/dimensions and scans message/link text; OCR and deeper image-content classification are not yet included. Attachment recovery retains URLs, not binary attachment copies.
- Verification thresholds are currently fixed at 80/60. The full previous verification scoring inputs and every legacy review workflow still need parity testing.
- Automation rules have a single text condition and bounded execution history; the original builder's complete condition set and retry policy still need porting.
- Recovery restores text and channel structure, but cannot recreate deleted binary attachments or guarantee an exact snapshot of every Discord permission/overwrite edge case.
- Support transcripts are stored locally and exported as bounded text chunks; the old attachment-export format and complete staff escalation controls still need parity validation.
- The dashboard's OAuth and server settings flow is ported, but every former account-link and per-module control needs a route-by-route parity audit.
- Native Android/Termux compilation and long-running Gateway/dashboard behavior must be validated on the actual device/toolchain. CI currently validates Linux Swift, not Android.
- Discord permission scopes, role hierarchy, rate limits, component expiry, and recovery behavior must be exercised in a disposable test server before production use.

## Verification before production

Run:

```sh
swift build -c release
swift test
swift run -c release
```

Back up the full `data/` directory before first startup. Keep the old bot deployment and data backup until the live Discord test matrix passes. Do not commit `.env`, bot tokens, OAuth secrets, or production data.

## Engineering hardening in progress

The Swift runtime is being hardened incrementally without changing the deployment model or replacing existing domain behavior.

- Persistent storage now publishes candidate values to actor memory only after the atomic file write succeeds. A failed write therefore cannot leave the running process ahead of durable state.
- Discord REST sessions now use explicit request and resource timeouts.
- Automatic retries for transient 5xx responses are limited to idempotent HTTP methods. Non-idempotent message and channel creation requests are not blindly replayed after ambiguous server failures.
- Regression tests cover successful persistence round-trips and the failed-write state invariant.
- The engineering and experience standard is documented in [docs/ENGINEERING.md](docs/ENGINEERING.md).

These changes are not a production-readiness declaration. The build and test suite must pass in CI, and the Termux and disposable-server validation matrix above remains mandatory.
