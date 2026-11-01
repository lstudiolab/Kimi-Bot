# Kimi dashboard on Termux

The dashboard is served by the same Node.js process as the Discord bot. It is not a separate Render service and does not use browser-local mock settings.

## Start

```sh
cd ~/Kimi-Bot
npm install
npm run check
npm test
npm start
```

Open `http://127.0.0.1:8787` in the browser on the Android device.

## Discord OAuth2

1. Open the Discord Developer Portal and select the same application used by Kimi.
2. Open OAuth2 and add the exact redirect URI: `https://YOUR_PUBLIC_HOST/auth/discord/callback`.
3. Copy the OAuth2 client secret. This is not the bot token.
4. Set these values in the private `.env` file:

```env
DISCORD_OAUTH_CLIENT_SECRET=your_oauth2_client_secret
DISCORD_OAUTH_REDIRECT_URI=https://YOUR_PUBLIC_HOST/auth/discord/callback
DASHBOARD_COOKIE_SECURE=true
```

5. Restart Kimi. The public verification page is `https://YOUR_PUBLIC_HOST/verify`.

Never put the OAuth client secret or bot token in dashboard JavaScript, GitHub Pages, or a public repository.

## Public access

The dashboard listens on `127.0.0.1:8787` by default. Keep that binding and expose it through a trusted HTTPS tunnel or reverse proxy that forwards to the Termux port. Discord OAuth requires the public HTTPS callback URL to exactly match the URI registered in the Developer Portal. Do not expose the dashboard over plain public HTTP.

If you need same-Wi-Fi access only, set `DASHBOARD_HOST=0.0.0.0` and open the phone's LAN address on port 8787. Do not port-forward that address directly to the internet.

## What Discord sign-in verifies

The `/verify` page uses the OAuth2 `identify` scope and confirms control of the Discord account that approved the request. The dashboard additionally requests `guilds` to show servers where the signed-in account has Manage Server permission and Kimi is present. This is identity authentication, not phone/email verification and not automatic role assignment.

## Dashboard permissions

- Viewing a server requires the signed-in Discord account to have Manage Server or Administrator permission and Kimi to be in that server.
- Installing or removing a library is restricted to the server owner.
- Enabling or disabling a system requires Manage Server permission.
- Bot credentials remain on the Termux host.
- The Activity page shows the latest in-memory Kimi process logs (up to 500 entries); restarting the process clears that short-term log buffer.
