# Run Kimi from Termux

Kimi's **Discord bot, dashboard backend, account authentication and configuration API run in the same Node.js process on your Android phone**. Account data is stored locally as JSON files in `data/auth/`. Do not deploy the dashboard backend to GitHub Pages or Render. GitHub is only the source repository.

## 1. Install on Android

Open Termux and run:

```sh
pkg update -y
pkg install -y git
git clone https://github.com/lstudiolab/Kimi-Bot.git
cd Kimi-Bot
bash scripts/termux-setup.sh
```

If the repository is already cloned, use `cd ~/Kimi-Bot` and run the setup script there.

## 2. Configure the bot

Copy the template if setup has not already created the file:

```sh
cp .env.example .env
nano .env
```

Set `DISCORD_TOKEN` and `CLIENT_ID`. Keep `DASHBOARD_HOST=127.0.0.1` and `DASHBOARD_PORT=8787`; the HTTPS tunnel connects to the backend locally.

You do not need Discord OAuth credentials. Kimi dashboard users create a Kimi account with an email and password. The password is stored as a scrypt hash, never as plaintext. Email ownership is not verified in this version.

Leave `DASHBOARD_OWNER_ID` blank or remove it if you do not need the developer-only process Logs page. If used, it must contain the Discord user ID of the developer account after that Discord identity is linked.

## 3. Start Kimi

Start Kimi in your first Termux session:

```sh
bash scripts/termux-start.sh
```

The bot and dashboard backend run together at `http://127.0.0.1:8787`.

On first visit to the dashboard, create a Kimi account. Then choose **Generate linking code** and copy the eight-digit code. In a Discord server where Kimi is installed, run:

```
/dashboard-link code:12345678
```

Replace `123456` with the code displayed by your dashboard. The code expires after 10 minutes. This links your Discord identity to your Kimi account without Discord OAuth. Kimi uses the linked identity only to check server membership and Manage Server or Administrator permissions.

## 4. Expose the dashboard securely

Keep the Node server on localhost. With Cloudflare Tunnel installed in Termux, open a second Termux session and run:

```sh
cd ~/Kimi-Bot
bash scripts/termux-tunnel.sh
```

For a quick test, Cloudflare prints a temporary `https://…trycloudflare.com` address. Open that HTTPS address to reach the dashboard. Keep `DASHBOARD_COOKIE_SECURE=true` for HTTPS access. A Quick Tunnel address changes when recreated, so it is suitable for testing only. For a permanent public dashboard URL, use a named Cloudflare Tunnel connected to a domain you control and keep that hostname fixed.

Keep the Termux process and tunnel process running. Android battery optimization can stop background processes; exempt Termux from battery optimization and keep the device powered when hosting continuously.

## Local account files

Kimi creates these files automatically on the Android phone:

- `data/auth/accounts.json` — account email, display name, password salt/hash and linked Discord identity.
- `data/auth/sessions.json` — hashed session-token records and expiration times.
- `data/auth/link-codes.json` — temporary Discord linking codes.

The auth directory is created with restricted permissions. These files are excluded from Git by the existing `.gitignore`. Back up the `data/` directory securely; losing it means losing local accounts and stored sessions.

## Access rules

- Visitors must sign in with a Kimi account before opening dashboard pages or APIs.
- Discord OAuth is not used.
- A Discord identity must be linked with a one-time `/dashboard-link` code before server selection.
- Only servers where Kimi is installed and the linked Discord user has Manage Server or Administrator permission are listed.
- A server must be explicitly selected before its settings load.
- Each guild API request checks membership and permission again; settings are scoped to that guild.
- Passwords, session tokens and bot credentials are never sent to the browser.
- GitHub Pages is static hosting and cannot run this backend. Use the Termux public HTTPS URL as the dashboard URL.
