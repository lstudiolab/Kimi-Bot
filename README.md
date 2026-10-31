# Timi Bot

Timi is a Discord bot built with **Node.js 24+** and **discord.js 14**. It provides configurable ticket panels, private support tickets and staff threads, transcripts, moderation controls, risk-based verification, self-service role pickers, reusable embeds, bot-join approval, and best-effort channel/message recovery.

## Requirements

- Node.js 24.17.0 or newer
- npm
- A Discord application and bot token
- OAuth2 scopes: `bot` and `applications.commands`
- Enable **Server Members Intent** and **Message Content Intent** in the Discord Developer Portal.

Grant only the permissions needed for the features you enable. Timi uses View Channels, Send Messages, Read Message History, Embed Links, Attach Files, Manage Channels, Manage Messages, Manage Threads, Create Private Threads, Send Messages in Threads, Manage Roles, Moderate Members, View Audit Log, Kick Members, and Ban Members.

## Termux installation

Install Node.js LTS and Git:

```sh
pkg update
pkg install -y nodejs-lts git
```

Check that Node.js is version 24 or newer:

```sh
node --version
npm --version
```

Update the existing Timi repository and run the JavaScript setup:

```sh
cd ~/Timi-Bot
git pull origin main
node scripts/termux-setup.js
```

The setup script installs npm dependencies and runs the tests. It creates `.env` from `.env.example` only when `.env` does not already exist. Existing credentials and the `data/` directory are preserved.

## Configuration

Edit `.env` from the repository root:

```env
DISCORD_TOKEN=your_discord_bot_token
CLIENT_ID=your_discord_application_id
GUILD_ID=
DATA_DIR=data
LOG_LEVEL=info
```

- `DISCORD_TOKEN`: Bot token from Developer Portal → Bot.
- `CLIENT_ID`: Application ID from Developer Portal → General Information.
- `GUILD_ID`: Optional development server ID. Leave blank for global slash-command registration.
- `DATA_DIR`: Persistent JSON data directory. Defaults to `data`.
- `LOG_LEVEL`: `debug`, `info`, `warn`, or `error`.

Never commit `.env` or share your bot token. If the token was exposed, reset it in the Developer Portal.

## Start Timi

```sh
cd ~/Timi-Bot
npm start
```

Timi registers its slash commands when it connects. To register them separately:

```sh
npm run deploy
```

For a persistent Termux session:

```sh
pkg install tmux
tmux new -s timi
cd ~/Timi-Bot
npm start
```

Detach with `Ctrl+B`, then `D`. Reopen with `tmux attach -t timi`. Android may still stop background processes; keep Termux exempt from battery optimization.

## Built-in libraries

Timi is free. Its first-party libraries are included in the same bot codebase, and each server can enable the libraries it needs. All four libraries are available without a subscription.

- **Moderation** — moderation actions and cases, auto moderation, server protection, anti-raid and bot approval, activity archiving, and moderation logs.
- **Support** — ticket setup, configurable panels, private tickets, staff threads, transcripts, permissions, and ticket logs.
- **Foundation** — server utilities, message and embed builder, welcome and goodbye messages, role picker, and member verification.
- **Developer** — TbScript block language, project editor, visual component kit, panel source editing, testing, version history, undo/redo, and .tdl import/export.

Only the server owner can install or uninstall a library. Use `/library-list` to see every available library, including Developer, and `/install-library` with the `libraryname` option to activate one. Uninstalling a library removes its commands and integrations but preserves its saved data and projects.

## Commands

- Core: `/timi-plan`, `/library-list`, `/install-library`, `/uninstall-library`.
- Moderation: `/moderation-settings`, `/automod-word add`, `/automod-word remove`, `/automod-word list`.
- Support: `/ticket-setup`, `/ticket-panel`, `/ticket-settings`.
- Foundation: `/ping`, `/server-info`, `/user-info`, `/avatar`, `/welcome-settings`, `/verify-settings`, `/verify-panel`, `/setup-role-picker`, `/create-embed`, `/edit-embed`, `/place-embed`.
- Developer: `/code`, `/code-edit`, `/code-list`, `/code-kit`, `/code-run`, `/code-stop`, `/code-history`, `/code-validate`, `/code-undo`, `/code-redo`, `/code-import`, `/code-export`, `/code-delete`, `/code-docs`, and `/code-template`.

## Timi Free

Timi is free to use. There is no Pro subscription, paid tier, or payment setup. Every built-in library, including Developer, is available to every server.

Each server has **5 MB** of saved configuration and project storage. The quota includes installed-library state, settings, customizations, TbScript projects, project history, and saved panel scripts. Message archives and recovery snapshots keep their existing retention limits and are not included. Timi rejects changes that would exceed the 5 MB allocation and preserves the server's last saved state.

Use `/timi-plan` to check storage usage.

## Developer library and TbScript

Developer is installed separately with `/install-library libraryname:Developer`. Only the server owner can create projects, edit panel source, run or stop projects, and manage the Developer workbench.

TbScript keeps the exact nested brace-block structure:

```text
{
   {title:"Welcome"}
   {description:"Hello, {user}!"}
   {addbutton:true:"Verify":"":false}
   {onclick(button):giverole:"Member"}
}
```

Each instruction is a `{}` block, nested blocks stay inside their parent blocks, `:` separates arguments, text values are quoted, and statements do not use semicolons. The transpiler parses nested blocks and validates them before creating Discord components. Supported blocks include `title`, `description`, `footer`, `author`, `imagelink`, `thumbnail`, `url`, `content`, `color`, `ephemeral`, `field`, `addbutton`, `onclick(button)`, `modal`, and nested `input`.

- `/code` creates a saved project. Saving never starts it automatically.
- `/code-edit` edits a project or supported ticket, verification, moderation, and role-picker panel source.
- `/code-kit` assembles component blocks into a selected project.
- `/code-template` creates a project from a starter template.
- `/code-validate` checks and transpiles a project without running it.
- `/code-run` tests a project; `/code-stop` disables its controls.
- `/code-undo` and `/code-redo` navigate recent source changes; `/code-history` lists saved versions.
- `/code-import` and `/code-export` exchange `.tdl` files (64 KB import limit).
- `/code-docs` opens the language reference.

TbScript does not execute JavaScript, shell commands, arbitrary network requests, or dynamically evaluated code. Only whitelisted Discord operations run. The current automatic repair adds missing closing braces; it does not invent or rewrite application logic. Discord modals are used for short source edits; larger files can be attached as `.tdl` files.

## Data and recovery

The primary store is `data/timi.json`; `data/timi.json.bak` is the previous known-good copy. Timi migrates compatible legacy ticket, moderation, verification, and recovery JSON files when their corresponding records are missing. Invalid primary data is preserved and recovered from the backup when possible; Timi refuses to silently reset corrupted data.

Channel snapshots and up to 25,000 human-authored messages per server are retained for seven days. Recovery is best-effort: recreated messages have new IDs, attachment URLs may expire, and deleted content that was never archived cannot be reconstructed.

## Development and tests

```sh
npm run check
npm test
```

The GitHub Actions workflow performs JavaScript syntax checks and runs the Node.js test suite on pushes and pull requests to `main`.
