import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";
import { LOCALE_NAMES } from "./i18n.js";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const DASHBOARD = path.join(ROOT, "dashboard");
const COOKIE = "kimi_session";
const SESSION_TTL = 30 * 24 * 60 * 60 * 1000;
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
const COMMAND_GROUPS = Object.freeze({
  Foundation:["setup","welcome","autorole","roles","embed-new","embed-edit","embed-post"],
  Security:["verify","verify-config","filter","security","moderation"],
  Support:["tickets","ticket-panel","ticket-config"],
  Scratch:["script","script-edit","scripts","script-run","script-stop","script-delete","script-export","script-import","script-history","script-check","script-undo","script-redo","script-kit","script-help","script-template"]
});
const COMMAND_NAMES = Object.freeze(Object.entries(COMMAND_GROUPS).flatMap(([bundle,names])=>names.map(name=>({name,bundle}))));

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

export function startDashboardServer({ config, client, store, manager, libraries, logger, syncGuildCommands, authStore }) {
  const authAttempts = new Map();
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
    return authStore.getSession(cookieValue(req, COOKIE));
  }
  function setSessionCookie(res, token) {
    const secure = config.dashboardCookieSecure ? "; Secure" : "";
    res.setHeader("Set-Cookie", COOKIE + "=" + encodeURIComponent(token) + "; HttpOnly; SameSite=Lax; Path=/; Max-Age=" + Math.floor(SESSION_TTL / 1000) + secure);
  }
  async function memberAccess(session, guild) {
    const discordId = session.discord?.id;
    if (!discordId) return null;
    if (guild.ownerId === discordId) return { owner: true, canManage: true };
    const member = guild.members.cache.get(discordId) || await guild.members.fetch(discordId).catch(() => null);
    if (!member) return null;
    const bits = member.permissions.bitfield;
    const canManage = (bits & 0x8n) === 0x8n || (bits & 0x20n) === 0x20n;
    return canManage ? { owner: false, canManage: true } : null;
  }
  async function authorizedGuild(session, guildId) {
    const guild = client.guilds.cache.get(guildId);
    if (!guild) return null;
    const access = await memberAccess(session, guild);
    return access ? { guild, owner: access.owner } : null;
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
      owner: guild.ownerId === session.discord?.id,
      canManage: true,
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
      if (method === "POST" && req.headers.origin) {
        const origin = new URL(req.headers.origin).host;
        if (origin !== req.headers.host) return send(res, 403, { error: "Cross-origin request blocked." });
      }
      if (method === "GET" && url.pathname === "/health") return send(res, 200, { ok: true, service: "kimi-dashboard", botReady: client.isReady() });

      if (method === "POST" && ["/auth/register", "/auth/login"].includes(url.pathname)) {
        const body = await parseBody(req);
        const ip = String(req.headers["cf-connecting-ip"] || req.socket.remoteAddress || "unknown");
        const attempt = authAttempts.get(ip) || { count: 0, resetAt: Date.now() + 15 * 60 * 1000 };
        if (attempt.resetAt <= Date.now()) { attempt.count = 0; attempt.resetAt = Date.now() + 15 * 60 * 1000; }
        if (attempt.count >= 8) return send(res, 429, { error: "Too many attempts. Wait 15 minutes and try again." });
        if (url.pathname === "/auth/register") {
          const result = authStore.createAccount({ email: body.email, password: body.password, displayName: body.displayName });
          if (result.error) return send(res, 400, { error: result.error });
          const token = authStore.createSession(result.account.id);
          setSessionCookie(res, token);
          authAttempts.delete(ip);
          logger.info("A new Kimi dashboard account was created.");
          return send(res, 201, { ok: true }, { "Set-Cookie": res.getHeader("Set-Cookie") });
        }
        const account = authStore.authenticate(body.email, body.password);
        if (!account) {
          attempt.count++;
          authAttempts.set(ip, attempt);
          return send(res, 401, { error: "Email or password is incorrect." });
        }
        authAttempts.delete(ip);
        const token = authStore.createSession(account.id);
        setSessionCookie(res, token);
        return send(res, 200, { ok: true }, { "Set-Cookie": res.getHeader("Set-Cookie") });
      }

      if (method === "POST" && url.pathname === "/auth/logout") {
        authStore.deleteSession(cookieValue(req, COOKIE));
        return send(res, 200, { ok: true }, { "Set-Cookie": COOKIE + "=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0" + (config.dashboardCookieSecure ? "; Secure" : "") });
      }

      if (url.pathname.startsWith("/api/")) {
        const session = sessionFor(req);
        if (!session) return send(res, 401, { error: "Sign in to your Kimi account to continue." });
        if (method === "GET" && url.pathname === "/api/me") {
          const account = authStore.publicAccount(session.account);
          return send(res, 200, {
            user: { id: account.id, username: account.email, email: account.email, globalName: account.displayName, displayName: account.displayName, createdAt: account.createdAt, discord: account.discord },
            bot: { ready: client.isReady(), tag: client.user?.tag || null, guildCount: client.guilds.cache.size },
            canViewLogs: Boolean(config.dashboardOwnerId && session.discord?.id === config.dashboardOwnerId),
            discordLinked: Boolean(session.discord)
          });
        }
        if (method === "POST" && url.pathname === "/api/discord/link-code") {
          const result = authStore.createLinkCode(session.account.id);
          return send(res, 200, { code: result.code, expiresAt: result.expiresAt });
        }
        if (method === "GET" && url.pathname === "/api/guilds") {
          if (!session.discord?.id) return send(res, 409, { error: "Connect your Discord account to load servers. Generate a linking code and use /dashboard-link in a server where Kimi is installed." });
          const guilds = [];
          for (const guild of client.guilds.cache.values()) {
            const access = await memberAccess(session, guild);
            if (access) guilds.push({ id: guild.id, name: guild.name, icon: guild.iconURL({ size: 64 }), owner: access.owner });
          }
          return send(res, 200, { guilds });
        }
        const analyticsMatch = url.pathname.match(/^\/api\/guilds\/(\d+)\/analytics$/);
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
          const rules=await context.guild.autoModerationRules.fetch().catch(()=>null);
          return send(res,200,{days,totals,topCommands,server:{members:context.guild.memberCount||0,channels:context.guild.channels.cache.size,roles:context.guild.roles.cache.size,rules:rules?rules.size:null},activeLibraries:(store.data.installed_libraries?.[analyticsMatch[1]]||[]).length,enabledSystems:Object.values(store.data.modules?.[analyticsMatch[1]]||{}).filter(value=>value!==false).length,uptimeSeconds:Math.floor(process.uptime())});
        }
        if (method === "GET" && url.pathname === "/api/logs") {
          if (!config.dashboardOwnerId || session.discord?.id !== config.dashboardOwnerId) {
            return send(res, 403, { error: "Process logs are restricted to the configured dashboard owner." });
          }
          return send(res, 200, { logs: logger.getRecent ? logger.getRecent(200) : [] });
        }
        const commandsMatch=url.pathname.match(/^\/api\/guilds\/(\d+)\/commands(?:\/([a-z0-9-]+))?$/);
        if(commandsMatch){
          const commandContext=await requireGuild(req,res,session,commandsMatch[1]);
          if(!commandContext)return;
          const settings=store.data.command_settings?.[commandsMatch[1]]||{};
          if(method==="GET"&&!commandsMatch[2])return send(res,200,{commands:COMMAND_NAMES.map(item=>({...item,enabled:settings[item.name]!==false,installed:(store.data.installed_libraries[commandsMatch[1]]||[]).includes(item.bundle)}))});
          if(method==="POST"&&commandsMatch[2]){
            const body=await parseBody(req);
            if(!COMMAND_NAMES.some(item=>item.name===commandsMatch[2])||typeof body.enabled!=="boolean")return send(res,400,{error:"Invalid command setting."});
            store.data.command_settings||={};
            store.data.command_settings[commandsMatch[1]]||={};
            store.data.command_settings[commandsMatch[1]][commandsMatch[2]]=body.enabled;
            store.save();
            logger.info("Dashboard "+(body.enabled?"enabled":"disabled")+" /"+commandsMatch[2]+" in guild "+commandsMatch[1]);
            return send(res,200,{ok:true,name:commandsMatch[2],enabled:body.enabled});
          }
        }
        const settingsMatch=url.pathname.match(/^\/api\/guilds\/(\d+)\/settings(?:\/([a-z-]+))?$/);
        if(settingsMatch){
          const settingsContext=await requireGuild(req,res,session,settingsMatch[1]);
          if(!settingsContext)return;
          if(method==="GET"&&!settingsMatch[2])return send(res,200,{language:store.data.languages?.[settingsMatch[1]]||"en-US",locales:Object.entries(LOCALE_NAMES).map(([value,label])=>({value,label}))});
          if(method==="POST"&&settingsMatch[2]==="language"){
            const body=await parseBody(req);
            if(!Object.hasOwn(LOCALE_NAMES,body.language))return send(res,400,{error:"Choose a supported language."});
            store.data.languages||={};
            store.data.languages[settingsMatch[1]]=body.language;
            store.save();
            logger.info("Dashboard changed server language to "+body.language+" in guild "+settingsMatch[1]);
            return send(res,200,{ok:true,language:body.language});
          }
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
            // authorizedGuild has already verified Manage Server or Administrator permission.
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

      const pagePath = url.pathname.replace(/\/+$/, "") || "/";
      if (method === "GET" && ["/verify", "/login", "/dashboard/verify"].includes(pagePath)) {
        return staticFile(res, "verify.html");
      }
      if (method === "GET" && ["/", "/dashboard", "/dashboard/index.html", "/index.html"].includes(pagePath)) {
        const session = sessionFor(req);
        if (!session) return redirect(res, "/login");
        return staticFile(res, "index.html");
      }
      if (method === "GET" && ["/app.js", "/styles.css", "/verify.js", "/dashboard/app.js", "/dashboard/styles.css", "/dashboard/verify.js"].includes(pagePath)) {
        return staticFile(res, pagePath.split("/").pop());
      }
      // This is a single-page dashboard. Serve its entry point for extensionless
      // client-side paths instead of returning a server-level 404.
      if (method === "GET" && !path.extname(pagePath)) {
        const session = sessionFor(req);
        if (!session) return redirect(res, "/login");
        return staticFile(res, "index.html");
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
    logger.info("Kimi account authentication is enabled with local JSON storage.");
  });
  return server;
}
