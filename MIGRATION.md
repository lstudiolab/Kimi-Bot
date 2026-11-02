# JavaScript to Swift migration

This branch replaces the Node.js runtime, Node package manifest and JavaScript test suite with a Swift Package Manager project. Application runtime source is now Swift.

## Ported
- Environment configuration, logging and persistent JSON store.
- Discord REST and Gateway websocket client.
- Global slash command registration and interaction router.
- App catalog and per-guild installation state.
- Foundation setup primitives.
- Kimi Lock rate detection and persisted policy.
- Verification scoring.
- Support ticket persistence and lifecycle.
- Automation rule persistence.
- Protection evaluation, embed validation and role-picker policy.
- Swift test target and CI build workflow.

## Not yet feature-equivalent
This is a language migration baseline, not a verified 1:1 feature port. The original dashboard browser application was removed with its JavaScript source; a Swift-hosted dashboard and its authentication/session endpoints are not implemented yet. Rich Discord modal/button/select-menu flows, full moderation sanctions, anti-nuke containment and rollback, ticket transcripts, automation trigger execution, localization, image-content analysis, subscription logic, and legacy data conversion still need parity work. Rate detections currently produce audit log findings and do not automatically apply sanctions. Do not replace the production runtime until Swift tests pass and every required Discord workflow has been tested in a private server.

The previous JSON data is preserved in the existing `data/` directory if copied, but schema conversion is not complete. Back up before migration.
