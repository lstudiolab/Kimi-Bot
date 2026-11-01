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

Set `DISCORD_TOKEN` and `CLIENT_ID` first. Also keep `DASHBOARD_HOST=127.0.0.1` and `DASHBOARD_PORT=8787`; the tunnel connects to the backend locally. You can add the OAuth secret and callback after you have a public tunnel URL.

Leave `DASHBOARD_OWNER_ID` blank or remove it if you do not need the developer-only process Logs page. It is not required for dashboard sign-in or server configuration.

## 3. Start the local backend

Start Kimi in your first Termux session:

```sh
bash scripts/termux-start.sh
```

The bot and dashboard backend now run at `http://127.0.0.1:8787`. OAuth login will remain disabled until its secret and public callback URL are configured; the local service can start before those values are known.

## 4. Expose the backend securely

Keep the Node server on localhost. With Cloudflare Tunnel installed in Termux, open a second Termux session and run:

```sh
cd ~/Kimi-Bot
bash scripts/termux-tunnel.sh
```

For a quick test, Cloudflare prints a temporary `https://…trycloudflare.com` address. In `.env`, set:

```env
DISCORD_OAUTH_CLIENT_SECRET=YOUR_DISCORD_OAUTH_CLIENT_SECRET
DISCORD_OAUTH_REDIRECT_URI=https://YOUR-TUNNEL-HOST/auth/discord/callback
DASHBOARD_COOKIE_SECURE=true
```

Add that exact callback URL in Discord Developer Portal → OAuth2 Redirects. Then restart Kimi in the first session; leave the tunnel running. Open the public HTTPS tunnel URL to sign in. The login page, dashboard, OAuth callback and API all use the same origin and session cookie. A Quick Tunnel address changes when recreated, so it is suitable for testing only. For a permanent public dashboard URL, use a named Cloudflare Tunnel connected to a domain you control and keep that hostname fixed.

Keep the Termux process and tunnel process running. Android battery optimization can stop background processes; exempt Termux from battery optimization and keep the device powered when hosting continuously.

## Access rules

- Unauthenticated visitors are redirected to the Discord sign-in page.
- The dashboard requires the Discord `identify guilds` OAuth scopes.
- Only servers where Kimi is installed and the signed-in user has Manage Server or Administrator permission are listed.
- A server must be explicitly selected before its settings load.
- Each guild API request checks membership and permission again; settings are scoped to that guild.
- The bot token and OAuth client secret stay in Termux and are never sent to the browser.
- GitHub Pages is static hosting and cannot run this backend. Use the Termux public HTTPS URL as the dashboard URL.
