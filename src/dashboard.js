import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DASHBOARD = path.join(ROOT, "dashboard");
const COOKIE = "kimi_session";
const OAUTH_COOKIE = "kimi_oauth_state";
const SESSION_TTL = 8 * 60 * 60 * 1000;
const MODULES = Object.freeze([
  { id: "welcome", name: "Welcome", library: "Foundation" },
  { id: "roles", name: "Role picker", library: "Foundation" },
  { id: "embeds", name: "Embeds", library: "Foundation" },
  { id: "verification", name: "Verification", library: "Security" },
  { id: "moderation", name: "Moderation", library: "Security" },
  { id: "protection", name: "Server protection", library: "Security" },
  { id: "recovery", name: "Recovery", library: "Security" },
  { id: "tickets", name: "Tickets", library: "Support" },
  { id: "scratch", name: "TbScript", library: "Scratch" }
]);
const LIBRARY_NAMES = new Set(["Foundation", "Security", "Support", "Scratch"]);
const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon"
};

function send(res, status, value, headers = {}) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    ...headers
  });
  res.end(JSON.stringify(value));
}
function redirect(res, location, headers = {}) {
  res.writeHead(302, { Location: location, "Cache-Control": "no-store", ...headers });
  res.end();
}
function cookieValue(req, name) {
  const raw = req.headers.cookie || "";
  for (const part of raw.split(";")) {
    const [key, ...value] = part.trim().split("=");
    if (key === name) return decodeURIComponent(value.join("="));
  }
  return "";
}
function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", chunk => {
      body += chunk;
      if (body.length > 65536) {
        reject(Object.assign(new Error("Request body is too large."), { status: 413 }));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (!body) return resolve({});
      try { resolve(JSON.parse(body)); }
      catch { reject(Object.assign(new Error("Invalid JSON body."), { status: 400 })); }
    });
    req.on("error", reject);
  });
}
function accountCreatedAt(id) {
  try { return new Date(Number((BigInt(id) >> 22n) + 1420070400000n)).toISOString(); }
  catch { return null; }
}
function safeNext(value) {
  return value === "/verify" ? "/verify" : "/";
}

export function startDashboardServer({ config, client, store, manager, libraries, logger, syncGuildCommands }) {
  const sessions = new Map();
  const pendingStates = new Map();
  const oauthReady = Boolean(config.oauthClientSecret && config.oauthRedirectUri);
  function recordAnalytics(guildId,metric,commandName=""){
    if(!guildId)return;
    const day=new Date().toISOString().slice(0,10);
    const all=store.data.analytics_requests||(store.data.analytics_requests={});
    const days=all[guildId]||(all[guildId]={});
    const row=days[day]||(days[day]={requests:0,commands:0,components:0,messages:0,joins:0,leaves:0,commandCounts:{}});
    if(metric==="request"){
      row.requests++;
      if(commandName){row.commands++;row.commandCounts[commandName]=(row.commandCounts[commandName]||0)+1;}
      else row.components++;
    }else if(Object.hasOwn(row,metric))row[metric]++;
    for(const key of Object.keys(days))if(Date.now()-Date.parse(key+"T00:00:00Z")>90*86400000)delete days[key];
    store.queueSave();
  }
  client.on("interactionCreate",interaction=>recordAnalytics(interaction.guildId,"request",interaction.isChatInputCommand()?interaction.commandName:""));
  client.on("messageCreate",message=>{if(message.guild&&!message.author.bot)recordAnalytics(message.guild.id,"messages");});
  client.on("guildMemberAdd",member=>recordAnalytics(member.guild.id,"joins"));
  client.on("guildMemberRemove",member=>recordAnalytics(member.guild.id,"leaves"));

  function sessionFor(req) {
    const id = cookieValue(req, COOKIE);
    const session = sessions.get(id);
    if (!session || session.expiresAt < Date.now()) {
      if (id) sessions.delete(id);
      return null;
    }
    return session;
  }
  function setSessionCookie(res, id) {
    const secure = config.dashboardCookieSecure ? "; Secure" : "";
    res.setHeader("Set-Cookie", COOKIE + "=" + encodeURIComponent(id) + "; HttpOnly; SameSite=Lax; Path=/; Max-Age=" + Math.floor(SESSION_TTL / 1000) + secure);
  }
  async function discordUserGuilds(session) {
    if (session.guilds && session.guildsExpiresAt > Date.now()) return session.guilds;
    const response = await fetch("https://discord.com/api/v10/users/@me/guilds", {
      headers: { Authorization: "Bearer " + session.accessToken }
    });
    if (!response.ok) throw new Error("Discord could not return your server list.");
    session.guilds = await response.json();
    session.guildsExpiresAt = Date.now() + 60_000;
    return session.guilds;
  }
  async function authorizedGuild(session, guildId) {
    const userGuilds = await discordUserGuilds(session);
    const userGuild = userGuilds.find(guild => guild.id === guildId);
    if (!userGuild) return null;
    const permissions = BigInt(userGuild.permissions || "0");
    const canManage = userGuild.owner === true || (permissions & 0x8n) === 0x8n || (permissions & 0x20n) === 0x20n;
    if (!canManage) return null;
    const guild = client.guilds.cache.get(guildId);
    if (!guild) return null;
    return { guild, owner: userGuild.owner === true || guild.ownerId === session.user.id };
  }
  async function requireGuild(req, res, session, guildId) {
    const context = await authorizedGuild(session, guildId);
    if (!context) {
      send(res, 403, { error: "You need Manage Server permission in a server where Kimi is installed." });
      return null;
    }
    return context;
  }
  function guildSnapshot(guild, session) {
    const installed = store.data.installed_libraries[guild.id] || [];
    const modules = MODULES.map(module => ({
      ...module,
      installed: installed.includes(module.library),
      enabled: store.data.modules?.[guild.id]?.[module.id] !== false
    }));
    return {
      id: guild.id,
      name: guild.name,
      icon: guild.iconURL({ size: 64 }),
      owner: guild.ownerId === session.user.id,
      libraries: [...LIBRARY_NAMES].map(name => ({
        name,
        installed: installed.includes(name),
        description: manager.get(name)?.description || ""
      })),
      modules
    };
  }
  function staticFile(res, file) {
    try {
      const data = fs.readFileSync(path.join(DASHBOARD, file));
      res.writeHead(200, {
        "Content-Type": MIME[path.extname(file)] || "application/octet-stream",
        "Cache-Control": file.endsWith(".html") ? "no-cache" : "public, max-age=300",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "strict-origin-when-cross-origin",
        "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' https://cdn.discordapp.com data:; connect-src 'self'; base-uri 'self'; form-action 'self' https://discord.com; frame-ancestors 'none'"
      });
      res.end(data);
    } catch {
      send(res, 404, { error: "Not found." });
    }
  }

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url || "/", "http://" + (req.headers.host || "localhost"));
    const method = req.method || "GET";
    try {
      if (method === "GET" && url.pathname === "/auth/discord") {
        if (!oauthReady) return redirect(res, "/verify?error=oauth-not-configured");
        const state = crypto.randomBytes(24).toString("hex");
        const browserId = crypto.randomBytes(24).toString("hex");
        for (const [key, item] of pendingStates) if (Date.now() - item.createdAt > 10 * 60 * 1000) pendingStates.delete(key);
        pendingStates.set(state, { next: safeNext(url.searchParams.get("next")), createdAt: Date.now(), browserId });
        const secure = config.dashboardCookieSecure ? "; Secure" : "";
        res.setHeader("Set-Cookie", OAUTH_COOKIE + "=" + browserId + "; HttpOnly; SameSite=Lax; Path=/auth/discord; Max-Age=600" + secure);
        const params = new URLSearchParams({
          client_id: config.clientId,
          response_type: "code",
          redirect_uri: config.oauthRedirectUri,
          scope: pending.next === "/verify" ? "identify" : "identify guilds",
          state
        });
        return redirect(res, "https://discord.com/oauth2/authorize?" + params.toString());
      }

      if (method === "GET" && url.pathname === "/auth/discord/callback") {
        const clearOAuthCookie = OAUTH_COOKIE + "=; HttpOnly; SameSite=Lax; Path=/auth/discord; Max-Age=0" + (config.dashboardCookieSecure ? "; Secure" : "");
        if (url.searchParams.has("error")) return redirect(res, "/verify?error=discord-denied", { "Set-Cookie": clearOAuthCookie });
        const code = url.searchParams.get("code") || "";
        const state = url.searchParams.get("state") || "";
        const pending = pendingStates.get(state);
        pendingStates.delete(state);
        const browserId = cookieValue(req, OAUTH_COOKIE);
        if (!oauthReady || !code || !pending || !browserId || pending.browserId !== browserId || Date.now() - pending.createdAt > 10 * 60 * 1000) {
          return redirect(res, "/verify?error=invalid-session", { "Set-Cookie": clearOAuthCookie });
        }
        const tokenResponse = await fetch("https://discord.com/api/v10/oauth2/token", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: config.clientId,
            client_secret: config.oauthClientSecret,
            grant_type: "authorization_code",
            code,
            redirect_uri: config.oauthRedirectUri
          })
        });
        if (!tokenResponse.ok) {
          logger.warn("Discord OAuth token exchange failed:", await tokenResponse.text());
          return redirect(res, "/verify?error=oauth-failed", { "Set-Cookie": clearOAuthCookie });
        }
        const token = await tokenResponse.json();
        const userResponse = await fetch("https://discord.com/api/v10/users/@me", {
          headers: { Authorization: "Bearer " + token.access_token }
        });
        if (!userResponse.ok) return redirect(res, "/verify?error=profile-failed", { "Set-Cookie": clearOAuthCookie });
        const user = await userResponse.json();
        const sessionId = crypto.randomBytes(32).toString("hex");
        sessions.set(sessionId, {
          user: { id: user.id, username: user.username, globalName: user.global_name || user.username, avatar: user.avatar },
          accessToken: token.access_token,
          scope: String(token.scope || (pending.next === "/verify" ? "identify" : "identify guilds")),
          expiresAt: Date.now() + Math.min(SESSION_TTL, Number(token.expires_in || 3600) * 1000),
          guilds: null,
          guildsExpiresAt: 0
        });
        setSessionCookie(res, sessionId);
        res.setHeader("Set-Cookie", [res.getHeader("Set-Cookie"), clearOAuthCookie]);
        return redirect(res, pending.next, { "Set-Cookie": [res.getHeader("Set-Cookie"), clearOAuthCookie] });
      }

      if (method === "POST" && url.pathname === "/auth/logout") {
        const id = cookieValue(req, COOKIE);
        if (id) sessions.delete(id);
        return send(res, 200, { ok: true }, { "Set-Cookie": COOKIE + "=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0" + (config.dashboardCookieSecure ? "; Secure" : "") });
      }

      if (url.pathname.startsWith("/api/")) {
        const session = sessionFor(req);
        if (!session) return send(res, 401, { error: "Sign in with Discord to continue." });
        if (method === "GET" && url.pathname === "/api/me") {
          return send(res, 200, {
            user: { ...session.user, createdAt: accountCreatedAt(session.user.id) },
            bot: { ready: client.isReady(), tag: client.user?.tag || null, guildCount: client.guilds.cache.size },
            canViewLogs: Boolean(config.dashboardOwnerId && session.user.id === config.dashboardOwnerId)
          });
        }
        if (method === "GET" && url.pathname === "/api/guilds") {
          if (!session.scope.split(/\s+/).includes("guilds")) return send(res, 403, { error: "Dashboard access requires Discord server-list permission.", reauth: true });
          const userGuilds = await discordUserGuilds(session);
          const available = userGuilds.filter(g => {
            const p = BigInt(g.permissions || "0");
            const canManage = g.owner || (p & 0x8n) === 0x8n || (p & 0x20n) === 0x20n;
            return canManage && client.guilds.cache.has(g.id);
          });
          return send(res, 200, { guilds: available.map(g => {
            const guild = client.guilds.cache.get(g.id);
            return { id: guild.id, name: guild.name, icon: guild.iconURL({ size: 64 }), owner: g.owner === true };
          }) });
        }
        const analyticsMatch = url.pathname.match(/^\\/api\\/guilds\\/(\\d+)\\/analytics$/);
        if (method === "GET" && analyticsMatch) {
          const context = await requireGuild(req, res, session, analyticsMatch[1]);
          if (!context) return;
          const stored = store.data.analytics_requests?.[analyticsMatch[1]] || {};
          const now = new Date();
          const days = Array.from({length:14},(_,index)=>{
            const date=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),now.getUTCDate()-(13-index)));
            const key=date.toISOString().slice(0,10);
            const row=stored[key]||{};
            return {date:key,requests:row.requests||0,commands:row.commands||0,components:row.components||0,messages:row.messages||0,joins:row.joins||0,leaves:row.leaves||0};
          });
          const since=Date.now()-30*86400000;
          const recent=Object.entries(stored).filter(([day])=>Date.parse(day+"T00:00:00Z")>=since).map(([,row])=>row);
          const totals=recent.reduce((sum,row)=>{for(const key of ["requests","commands","components","messages","joins","leaves"])sum[key]+=row[key]||0;return sum;},{requests:0,commands:0,components:0,messages:0,joins:0,leaves:0});
          const commandCounts={};
          for(const row of recent)for(const [name,count] of Object.entries(row.commandCounts||{}))commandCounts[name]=(commandCounts[name]||0)+count;
          const topCommands=Object.entries(commandCounts).sort((a,b)=>b[1]-a[1]).slice(0,6).map(([name,count])=>({name,count}));
          return send(res,200,{days,totals,topCommands,activeLibraries:(store.data.installed_libraries?.[analyticsMatch[1]]||[]).length,enabledSystems:Object.values(store.data.modules?.[analyticsMatch[1]]||{}).filter(value=>value!==false).length,uptimeSeconds:Math.floor(process.uptime())});
        }
        if (method === "GET" && url.pathname === "/api/logs") {
          if (!config.dashboardOwnerId || session.user.id !== config.dashboardOwnerId) {
            return send(res, 403, { error: "Process logs are restricted to the configured dashboard owner." });
          }
          return send(res, 200, { logs: logger.getRecent ? logger.getRecent(200) : [] });
        }
        const guildMatch = url.pathname.match(/^\/api\/guilds\/(\d+)(?:\/(modules|libraries)\/([a-zA-Z-]+))?$/);
        if (guildMatch) {
          const guildId = guildMatch[1];
          const context = await requireGuild(req, res, session, guildId);
          if (!context) return;
          if (method === "GET" && !guildMatch[2]) return send(res, 200, guildSnapshot(context.guild, session));
          if (method === "POST" && guildMatch[2] === "modules") {
            const body = await parseBody(req);
            const module = MODULES.find(item => item.id === guildMatch[3]);
            if (!module || typeof body.enabled !== "boolean") return send(res, 400, { error: "Invalid system or enabled value." });
            if (!(store.data.installed_libraries[guildId] || []).includes(module.library)) {
              return send(res, 409, { error: "Install the " + module.library + " library before changing this system." });
            }
            store.data.modules[guildId] ||= {};
            store.data.modules[guildId][module.id] = body.enabled;
            store.save();
            logger.info("Dashboard changed " + module.id + " to " + (body.enabled ? "enabled" : "disabled") + " in guild " + guildId);
            return send(res, 200, { ok: true, module: module.id, enabled: body.enabled });
          }
          if (method === "POST" && guildMatch[2] === "libraries") {
            const body = await parseBody(req);
            const name = guildMatch[3];
            if (!LIBRARY_NAMES.has(name) || !["install", "uninstall"].includes(body.action)) {
              return send(res, 400, { error: "Invalid library action." });
            }
            if (!context.owner) return send(res, 403, { error: "Only the server owner can install or remove libraries." });
            if (body.action === "install") {
              const result = manager.install(guildId, name);
              if (!result.ok) return send(res, 409, { error: result.error });
              try {
                await syncGuildCommands(guildId);
                if (libraries[name]?.ready) await libraries[name].ready(context.guild);
                if (libraries[name]?.onInstall) await libraries[name].onInstall(context.guild);
              } catch (error) {
                manager.uninstall(guildId, name);
                await syncGuildCommands(guildId).catch(() => {});
                throw error;
              }
            } else {
              const result = manager.uninstall(guildId, name);
              if (!result.ok) return send(res, 409, { error: result.error });
              try {
                if (libraries[name]?.onUninstall) await libraries[name].onUninstall(context.guild);
                await syncGuildCommands(guildId);
              } catch (error) {
                manager.install(guildId, name);
                await syncGuildCommands(guildId).catch(() => {});
                throw error;
              }
            }
            logger.info("Dashboard " + body.action + "ed " + name + " in guild " + guildId);
            return send(res, 200, guildSnapshot(context.guild, session));
          }
        }
        return send(res, 404, { error: "API route not found." });
      }

      if (method === "GET" && url.pathname === "/") return staticFile(res, "index.html");
      if (method === "GET" && url.pathname === "/verify") return staticFile(res, "verify.html");
      if (method === "GET" && url.pathname === "/login") return staticFile(res, "verify.html");
      if (method === "GET" && ["/index.html", "/app.js", "/styles.css", "/verify.js"].includes(url.pathname)) {
        return staticFile(res, url.pathname.slice(1));
      }
      return send(res, 404, { error: "Not found." });
    } catch (error) {
      logger.error("Dashboard request failed:", error);
      if (!res.headersSent) send(res, error.status || 500, { error: error.status ? error.message : "The dashboard could not complete this request." });
      else res.destroy();
    }
  });

  server.listen(config.dashboardPort, config.dashboardHost, () => {
    logger.info("Kimi dashboard listening on http://" + config.dashboardHost + ":" + config.dashboardPort);
    if (!oauthReady) logger.warn("Discord sign-in is disabled until DISCORD_OAUTH_CLIENT_SECRET and DISCORD_OAUTH_REDIRECT_URI are configured.");
  });
  return server;
}
