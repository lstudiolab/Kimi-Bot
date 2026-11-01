# Run Kimi from Termux

Kimi's **bot, dashboard backend, Discord OAuth callback, sessions and configuration API all run in the same Node.js process on Termux**. Do not deploy the dashboard backend to GitHub Pages or Render. GitHub is only the source repository.

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

## 2. Configure Discord

Copy the template if setup has not already created the file:

```sh
cp .env.example .env
nano .env
```

Set:

- `DISCORD_TOKEN`: the bot token.
- `CLIENT_ID`: the Discord application ID.
- `DISCORD_OAUTH_CLIENT_SECRET`: the OAuth2 client secret from the same Discord application.
- `DISCORD_OAUTH_REDIRECT_URI`: the public HTTPS URL ending in `/auth/discord/callback`.
- `DASHBOARD_HOST=127.0.0.1` and `DASHBOARD_PORT=8787`: keep the backend bound to localhost. The tunnel connects to it locally.

Leave `DASHBOARD_OWNER_ID` blank or remove it if you do not need the developer-only process Logs page. It is not required for dashboard sign-in or server configuration.

In Discord Developer Portal → OAuth2, add the exact same redirect URI from `.env`. OAuth scopes are `identify` and `guilds`.

## 3. Expose the backend securely

Keep the Node server on localhost. Use a HTTPS tunnel to make the Termux-hosted site reachable from your phone or other devices.

With Cloudflare Tunnel installed in Termux, run this in a second Termux session:

```sh
bash scripts/termux-tunnel.sh
```

For a quick test, Cloudflare prints a temporary `https://…trycloudflare.com` address. Set:

```env
DISCORD_OAUTH_REDIRECT_URI=https://YOUR-TUNNEL-HOST/auth/discord/callback
DASHBOARD_COOKIE_SECURE=true
```

Add that exact callback URL in Discord Developer Portal, then restart Kimi. A Quick Tunnel address changes when recreated, so it is suitable for testing only. For a permanent public dashboard URL, use a named Cloudflare Tunnel connected to a domain you control and keep that hostname fixed.

## 4. Start Kimi

In the project directory:

```sh
bash scripts/termux-start.sh
```

The dashboard is served by the same backend at `http://127.0.0.1:8787`. Open the public HTTPS tunnel URL to sign in and configure servers. The public login page, dashboard pages, OAuth callback and API all use the same origin and session cookie.

Keep the Termux process and tunnel process running. Android battery optimization can stop background processes; exempt Termux from battery optimization and keep the device powered when hosting continuously.

## Access rules

- Unauthenticated visitors are redirected to the Discord sign-in page.
- The dashboard requires the Discord `identify guilds` OAuth scopes.
- Only servers where Kimi is installed and the signed-in user has Manage Server or Administrator permission are listed.
- A server must be explicitly selected before its settings load.
- Each guild API request checks membership and permission again; settings are scoped to that guild.
- The bot token and OAuth client secret stay in Termux and are never sent to the browser.
- GitHub Pages is static hosting and cannot run this backend. Use the Termux public HTTPS URL as the dashboard URL.
