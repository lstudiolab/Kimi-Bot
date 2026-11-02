# Kimi Swift dashboard

The dashboard is served by the same Swift process as the Discord bot. It uses server-rendered HTML and ordinary form submissions; there is no browser-side JavaScript bundle and no separate Render service.

## Configure Discord OAuth2

1. Open the Discord Developer Portal and select Kimi's application.
2. Under OAuth2, add the exact redirect URI: `https://YOUR_PUBLIC_HOST/oauth/callback`.
3. Copy the OAuth2 client secret. This is separate from the bot token.
4. Set these values in the private `.env` file:

```env
DASHBOARD_HOST=127.0.0.1
DASHBOARD_PORT=8787
DISCORD_OAUTH_CLIENT_SECRET=your_oauth2_client_secret
DISCORD_OAUTH_REDIRECT_URI=https://YOUR_PUBLIC_HOST/oauth/callback
```

Restart Kimi and open the HTTPS hostname. The dashboard redirects to Discord for sign-in and requests only `identify` and `guilds` scopes. No Kimi email/password account is required.

## Network exposure

The dashboard binds to localhost by default. Expose port 8787 through a trusted HTTPS tunnel or reverse proxy. Do not expose the dashboard directly over public HTTP. Keep `DASHBOARD_HOST=127.0.0.1` when using a tunnel.

For same-Wi-Fi access only, `DASHBOARD_HOST=0.0.0.0` can bind to the LAN interface; do not port-forward it to the public internet.

## Access control

- A user must have Manage Server or Administrator permission in a server.
- Kimi must be installed in that server.
- App installation and removal are restricted to the server owner.
- OAuth access tokens and session cookies remain server-side.
- Session cookies are HttpOnly and SameSite=Lax; HTTPS callbacks enable the Secure attribute.
- The dashboard is intentionally server-rendered. Browser JavaScript is not required.
