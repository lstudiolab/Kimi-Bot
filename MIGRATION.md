# Migration status

The Node backend and npm build configuration have been replaced by a Swift Package Manager runtime in this branch.

Implemented: configuration, local persistent storage primitive, Discord REST transport, Gateway websocket identify/heartbeat/reconnect, global slash-command registration, and an initial interaction router.

Not yet at feature parity: all former Kimi modules and interactions require detailed porting. Kimi Lock sanctions and anti-nuke restoration, complete Support lifecycle/transcripts, verification panels, role pickers, embed modals, automation execution, dashboard APIs/authentication, localization and complete data-schema migration are not complete. Existing browser-side dashboard JavaScript remains because browsers do not execute Swift directly; it needs a Swift server API and a separately designed browser client migration.

Do not deploy this runtime as a production replacement until feature parity, build/test validation on Termux, and legacy data migration are complete.
