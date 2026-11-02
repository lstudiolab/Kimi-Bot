# Kimi Automations

Kimi Automations is an owner-facing visual flow builder inspired by the simplicity of Apple Shortcuts. It is not a scripting language: owners combine supported blocks and Kimi handles validation, permissions, execution and reporting.

## Flow model

Each automation is an ordered flow:

1. **Trigger** — member joins, member leaves, or a new message.
2. **Condition** — every time, account age, invite/link detection, or a custom phrase match.
3. **Actions** — send a templated message, assign/remove a role, delete the triggering message, or apply a temporary timeout.

## Limits and safeguards

- Up to 25 automations per server.
- Up to 8 ordered actions per automation.
- Message actions are limited to 1,800 characters.
- Timeout actions are limited to Discord's 28-day maximum.
- Role actions reject managed roles, the @everyone role, and roles at or above Kimi's highest role.
- Channel and permission checks run during setup; role hierarchy and permissions are checked again at execution time.
- Action failures are logged independently, so one failed step does not silently prevent later steps from running.
- Background execution uses a bounded queue with in-flight deduplication and backpressure.

## Current trigger coverage

- Member joins
- Member leaves
- Member messages

Automations are stored per server and survive restarts. The editor currently supports creating, enabling, disabling and deleting flows. Editing existing flow blocks and scheduled/time-based triggers are future extensions; they are not represented as available features yet.
