# Timi Bot

Timi is a Discord bot built with Node.js 24+ and discord.js 14. It is designed around four optional libraries: Foundation, Security, Support, and Scratch. Timi has no paid tier or AI API dependency.

## Requirements

- Node.js 24.17 or newer
- npm and Git
- A Discord application and bot token
- OAuth2 scopes: `bot` and `applications.commands`
- Enable **Server Members Intent** and **Message Content Intent** in the Discord Developer Portal

Grant only the permissions needed by the systems enabled in your server. Security and ticket recovery features need elevated permissions such as View Audit Log, Manage Channels, Manage Messages, Manage Roles, Moderate Members, Kick Members, and Ban Members.

## Install or update on Termux

Install Node.js and Git:

```sh
pkg update
pkg install -y nodejs-lts git
```

Check Node.js:

```sh
node --version
npm --version
```

Update Timi and install dependencies:

```sh
cd ~/Timi-Bot
git pull origin main
node scripts/termux-setup.js
```

The setup script installs npm dependencies, checks the JavaScript modules, and runs the tests. It creates `.env` from `.env.example` only when `.env` does not already exist. It does not overwrite existing credentials or the `data/` directory.

## Configuration

Set these values in `.env`:

```env
DISCORD_TOKEN=your_discord_bot_token
CLIENT_ID=your_discord_application_id
GUILD_ID=
DATA_DIR=data
LOG_LEVEL=info
```

- `DISCORD_TOKEN`: Bot token from Developer Portal → Bot.
- `CLIENT_ID`: Application ID from Developer Portal → General Information.
- `GUILD_ID`: Optional development server ID. Leave blank for global core commands.
- `DATA_DIR`: Persistent JSON data directory. Defaults to `data`.
- `LOG_LEVEL`: `debug`, `info`, `warn`, or `error`.

Never commit `.env` or share your bot token. Reset the token in the Developer Portal if it is exposed.

## Start Timi

```sh
cd ~/Timi-Bot
npm start
```

Timi registers core commands globally and library commands for each server where that library is installed. It also synchronizes the current command set on startup, so older command names are removed when the bot restarts.

For a persistent Termux session:

```sh
pkg install tmux
tmux new -s timi
cd ~/Timi-Bot
npm start
```

Detach with `Ctrl+B`, then `D`. Reopen with `tmux attach -t timi`. Android may stop background processes; exempt Termux from battery optimization.

## Libraries

Timi is free. Every library is included in the same bot. The server owner installs or uninstalls libraries with the core commands.

| Library | What it contains |
|---|---|
| **Foundation** | Private setup channels, welcome and goodbye messages, automatic roles, role pickers, reusable embeds |
| **Security** | Verification, AutoMod, anti-spam, anti-nuke monitoring, raid containment, bot approval, image checks, security audit and recovery |
| **Support** | Ticket setup, persistent ticket panels, private channels, staff threads, transcripts and logs |
| **Scratch** | TbScript projects, source editor, component kit, panel scripts, validation, test runs, version history, undo/redo and .tdl import/export |

Use `/libraries` to see the libraries and installation state. Use `/install library:<name>` and `/uninstall library:<name>` to manage them. Valid names are Foundation, Security, Support, and Scratch. Previous names Moderation and Developer are accepted as aliases when older configuration is migrated.

## Commands

**Core**
- `/plan` — view the free plan and server storage.
- `/libraries` — list the four libraries and their installation state.
- `/install` — install one library (server owner only).
- `/uninstall` — disable one library (server owner only).

**Foundation**
- `/setup` — create private `#timi-log`, `#timi-confirmations`, and `#timi-settings` channels.
- `/welcome` — configure welcome and goodbye channels and templates.
- `/autorole` — set or disable automatic role assignment.
- `/roles` — configure a self-service role picker.
- `/embed-new`, `/embed-edit`, `/embed-post` — create, edit, and post reusable embeds.

**Security**
- `/verify-config` — configure the verified role, required role, minimum account age, review channel and panel text.
- `/verify` — publish or update the verification panel.
- `/moderation` — open the persistent moderation settings panel.
- `/filter add`, `/filter remove`, `/filter list` — manage blocked phrases.
- `/security` — audit common server security settings.

Image checks run when a member uploads an image and either mentions Timi or replies to one of Timi's messages with the image.

Verification uses the configured score thresholds: 80+ passes and assigns the verified role, 60–79 (or an account below the configured minimum age) goes to manual review with manager-only Approve and Reject controls, and scores below 60 trigger a kick attempt. Each member can complete verification only once per server.

**Support**
- `/tickets` — create or reuse Timi's private setup channels and the ticket category.
- `/ticket-panel` — publish or update the ticket panel.
- `/ticket-config` — configure ticket text, support roles and destinations.

**Scratch**
- `/script` — create a TbScript project.
- `/script-edit` — edit a project or supported panel script.
- `/scripts` — list saved projects.
- `/script-run`, `/script-stop` — test or stop a project.
- `/script-check` — validate source without running it.
- `/script-template`, `/script-kit`, `/script-help` — create and learn TbScript components.
- `/script-history`, `/script-undo`, `/script-redo` — manage project versions.
- `/script-import`, `/script-export`, `/script-delete` — import, export, or remove projects.

Library commands require Manage Server permission unless a command explicitly requires the server owner. Ticket opening, verification actions, role selection, and published TbScript role buttons are member-facing.

## Security behavior

- New bot joins are sent to the private confirmation channel. Timi posts the approval request before applying temporary channel restrictions.
- New accounts younger than three days receive a 10-minute timeout when Timi can moderate them; accounts younger than seven days are logged for review.
- Six joins in ten seconds trigger a warning. Eight joins in ten seconds trigger a 60-second raid-containment window and 10-minute timeouts for manageable non-administrator accounts. This is timeout-based containment, not a full server lockdown.
- Sensitive audit activity is monitored for destructive channel, role, webhook, permission and member-role changes. Repeated activity can trigger a 60-minute timeout where role hierarchy permits.
- High-impact role permission changes and dangerous role assignments are logged for owner review. Timi does not silently revert role grants.
- `/security` performs a configuration audit. It is not a penetration test and cannot detect compromised accounts, leaked tokens, malicious code, or every permission path.

Automated moderation is configurable. The default burst threshold is 20 messages per member per channel within 60 seconds. Phrase, invite, mention, capitalization and link checks are separate signals. Configure sanctions carefully and review the private logs.

## Free image tools (no AI API)

Timi does not upload images to a paid AI service. Optional local tools provide:

- Image format, dimensions, byte count and SHA-256.
- OCR with Tesseract (English).
- QR decoding with ZBar.
- Perceptual duplicate checks with ImageMagick.
- Exact duplicate checks in a bounded in-memory history.
- URL extraction from OCR and QR content, plus simple phishing heuristics.

Optional Termux packages:

```sh
pkg update
pkg install tesseract zbar imagemagick
```

Each image is limited to 8 MB and 40 megapixels (maximum side 12,000 pixels); up to three images are checked per request, and temporary files are deleted after processing. Timi rejects oversized images and does not store the image itself.

These tools do **not** provide AI image understanding or a reliable visual classifier for nudity, violence or graphic content. OCR can miss text, and a clean report does not prove an image or link is safe. Heuristic flags do not automatically punish users.

## Timi Free and storage

Timi has one free plan. There is no Pro plan, subscription or payment setup. All four libraries are available to every server.

Each server has a fixed 5 MB allocation for saved settings, customizations, embeds, projects and panel scripts. Timi rejects writes that exceed the allocation and preserves the previous saved state. Transient image-processing files and the bounded in-memory duplicate cache are not persisted as server content.

Use `/plan` to check the current allocation.

## TbScript

TbScript is Timi's small, readable scripting language for Discord panels and basic server automation. It combines Python-like readability with Lua-style end blocks. Scripts use four spaces for indentation, do not need semicolons, and never execute JavaScript or shell code.

### Quick example

~~~tbscript
panel:
    title "Ticket Support"
    description "Click below to create a private ticket."
    color "#808080"
    button "Open Ticket" : ticket

onclick ticket:
    create channel "ticket"
    make private
    allow @author
    reply "Your ticket has been created."
end
~~~

### Events and conditions

~~~tbscript
on member join:
    send #welcome "Welcome @author to @server!"
end
~~~

~~~tbscript
on message create:
    if message.content == "hello":
        reply "Hello!"
    else:
        reply "Welcome. How can I help?"
    end
end
~~~

### Language keywords

**Panel and UI**
- panel: starts a panel definition.
- title "text": embed title.
- description "text": embed description.
- color "#808080": six-digit hexadecimal embed color.
- footer "text": embed footer.
- author "text": embed author.
- image "https://...": embed image.
- thumbnail "https://...": embed thumbnail.
- url "https://...": embed title URL.
- content "text": message content.
- field "name" "value": adds an embed field.
- button "label" : id: adds a button with a unique script ID.
- ephemeral true|false: makes the test response visible only to the command user when true.

**Events and flow**
- onclick id: defines what happens when the button with that ID is clicked.
- on member join: runs when a member joins while the project is running.
- on message create: runs when a non-bot member sends a message while the project is running.
- if condition: runs its indented actions when a supported condition is true.
- else: provides an optional alternative branch for the matching if.
- end: closes an onclick, on, or if block. A panel ends when the next top-level statement begins.

**Actions**
- reply "text": replies to the current button interaction or message.
- send #channel "text": sends a message to a channel by name or channel mention.
- create channel "name": creates a private text channel. The @everyone view permission is denied from creation.
- make private: re-applies the private-channel permission.
- allow @author: grants the current author access to the channel created by the current action.
- allow "Role Name": grants a server role access to that newly created channel.
- give role "Role Name": assigns a safe role to the current author.
- remove role "Role Name": removes a safe role from the current author.

**Supported conditions**
- message.content == "text" and message.content != "text".
- author.id == "Discord ID" and author.id != "Discord ID".
- author.is_admin, author.is_owner, author.bot, and member.is_admin.
- true and false.

**Text placeholders**
- @author: current user mention, without triggering an automatic ping.
- @authorID: current user ID.
- @server and @serverID: current server name and ID.
- @channel: current channel mention.
- @memberCount: current server member count.

### Running and publishing

- /script creates a project.
- /script-edit edits a project or supported Timi panel.
- /script-check validates source without running it.
- /script-run publishes a panel or activates event handlers.
- /script-stop disables its buttons and event handlers.
- /script-template, /script-kit, and /script-help provide starter code and reference material.
- /script-export and /script-import transfer .tdl source files.

Projects are saved but never run automatically. Only a server owner or a member with the required server-management permission can create, edit, validate, run, or stop projects. Button actions are available to members who can access the published panel.

### Safety and limits

TbScript is an allowlisted language, not an unrestricted programming runtime. It has no eval, JavaScript, shell, arbitrary HTTP, filesystem, or dynamic module-import statements. Unknown keywords and malformed syntax are rejected before saving or running.

- Source files are limited to 64 KB and 2,000 lines.
- Indentation uses groups of four spaces; tabs are rejected.
- Block structure is validated before execution.
- Discord embed, message, button, and field limits are checked before rendering.
- Channel creation starts private; the bot must have Manage Channels.
- Role changes reject managed, @everyone, privileged, or higher-than-Timi roles and require Manage Roles.
- send only targets a text channel in the current server.
- Event handlers only run for projects explicitly started with /script-run; /script-stop disables them.
- Imported .tdl files are limited to 64 KB and must be uploaded as Discord attachments.
- Project history retains up to ten previous versions.

The previous nested-brace TbScript format remains accepted for existing projects. New projects and templates use the simpler syntax shown above.

## Data and recovery

The primary store is `data/timi.json`; `data/timi.json.bak` is the previous known-good copy. Compatible legacy settings are migrated without overwriting existing records. Invalid primary data is preserved and recovered from the backup when possible; Timi refuses to silently reset corrupted data.

Recovery keeps channel configuration snapshots and a rolling archive capped at 4 MB per server, with a maximum of 25,000 human-authored messages retained for up to seven days. The oldest messages are pruned first when either limit is reached. Recreated messages have new IDs. Attachment URLs may expire, and content that was never archived cannot be reconstructed. Recovery is best-effort, not a guaranteed restore service.

## Development checks

```sh
npm run check
npm test
```

GitHub Actions runs syntax, import and test checks on pushes and pull requests to `main`.
