import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const SESSION_TTL = 30 * 24 * 60 * 60 * 1000;
const LINK_TTL = 10 * 60 * 1000;
const WEB_TOKEN_TTL = 10 * 60 * 1000;
const MAX_ACCOUNTS = 10000;

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, "utf8")); }
  catch { return fallback; }
}
function writeJson(file, value) {
  const temp = file + ".tmp";
  fs.writeFileSync(temp, JSON.stringify(value, null, 2), { mode: 0o600 });
  fs.renameSync(temp, file);
  try { fs.chmodSync(file, 0o600); } catch {}
}

export class AuthStore {
  constructor(dataDir, logger) {
    this.dir = path.resolve(dataDir, "auth");
    fs.mkdirSync(this.dir, { recursive: true, mode: 0o700 });
    try { fs.chmodSync(this.dir, 0o700); } catch {}
    this.accountsFile = path.join(this.dir, "accounts.json");
    this.sessionsFile = path.join(this.dir, "sessions.json");
    this.linksFile = path.join(this.dir, "link-codes.json");
    this.webTokensFile = path.join(this.dir, "web-tokens.json");
    this.accounts = readJson(this.accountsFile, { accounts: [] });
    this.sessions = readJson(this.sessionsFile, {});
    this.links = readJson(this.linksFile, {});
    this.webTokens = readJson(this.webTokensFile, {});
    if (!this.accounts || typeof this.accounts !== "object" || !Array.isArray(this.accounts.accounts)) this.accounts = { accounts: [] };
    else this.accounts.accounts = this.accounts.accounts.filter(account => account && typeof account === "object" && typeof account.id === "string" && typeof account.email === "string" && /^[a-f0-9]{32}$/i.test(account.passwordSalt || "") && /^[a-f0-9]{128}$/i.test(account.passwordHash || ""));
    for (const account of this.accounts.accounts) {
      account.guilds = Array.isArray(account.guilds) ? account.guilds.filter(link => link && typeof link === "object" && /^\d{15,22}$/.test(String(link.id || "")) && /^\d{15,22}$/.test(String(link.linkedBy || ""))) : [];
      if (account.discord && (typeof account.discord !== "object" || !/^\d{15,22}$/.test(String(account.discord.id || "")))) account.discord = null;
    }
    if (!this.sessions || typeof this.sessions !== "object" || Array.isArray(this.sessions)) this.sessions = {};
    if (!this.links || typeof this.links !== "object" || Array.isArray(this.links)) this.links = {};
    if (!this.webTokens || typeof this.webTokens !== "object" || Array.isArray(this.webTokens)) this.webTokens = {};
    this.logger = logger;
    this.linkFailures = new Map();
    this.prune();
  }
  saveAccounts() { writeJson(this.accountsFile, this.accounts); }
  saveSessions() { writeJson(this.sessionsFile, this.sessions); }
  saveLinks() { writeJson(this.linksFile, this.links); }
  saveWebTokens() { writeJson(this.webTokensFile, this.webTokens); }
  prune() {
    const now = Date.now();
    let sessionsChanged = false, linksChanged = false, webTokensChanged = false;
    for (const [key, value] of Object.entries(this.sessions)) if (!value || typeof value.accountId !== "string" || !Number.isFinite(value.expiresAt) || value.expiresAt <= now) { delete this.sessions[key]; sessionsChanged = true; }
    for (const [key, value] of Object.entries(this.links)) if (!value || typeof value.accountId !== "string" || !Number.isFinite(value.expiresAt) || value.expiresAt <= now) { delete this.links[key]; linksChanged = true; }
    if (sessionsChanged) this.saveSessions();
    for (const [key, value] of Object.entries(this.webTokens)) if (!value || typeof value.accountId !== "string" || !Number.isFinite(value.expiresAt) || value.expiresAt <= now) { delete this.webTokens[key]; webTokensChanged = true; }
    if (linksChanged) this.saveLinks();
    if (webTokensChanged) this.saveWebTokens();
  }
  normalizeEmail(email) { return String(email || "").trim().toLowerCase(); }
  createAccount({ email, password, displayName }) {
    const normalized = this.normalizeEmail(email);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized) || normalized.length > 254) return { error: "Enter a valid email address." };
    if (String(password || "").length < 10 || String(password).length > 128) return { error: "Password must be between 10 and 128 characters." };
    if (this.accounts.accounts.some(account => account.email === normalized)) return { error: "An account with this email already exists." };
    if (this.accounts.accounts.length >= MAX_ACCOUNTS) return { error: "Kimi account capacity has been reached. Contact support." };
    const salt = crypto.randomBytes(16).toString("hex");
    const passwordHash = crypto.scryptSync(String(password), salt, 64).toString("hex");
    const account = {
      id: crypto.randomUUID(),
      email: normalized,
      displayName: String(displayName || "").trim().slice(0, 40) || normalized.split("@")[0],
      passwordSalt: salt,
      passwordHash,
      createdAt: new Date().toISOString(),
      discord: null
    };
    this.accounts.accounts.push(account);
    this.saveAccounts();
    return { account: this.publicAccount(account) };
  }
  publicAccount(account) {
    return { id: account.id, email: account.email, displayName: account.displayName, createdAt: account.createdAt, discord: account.discord ? { id: account.discord.id, username: account.discord.username, globalName: account.discord.globalName, avatar: account.discord.avatar } : null };
  }
  authenticate(email, password) {
    if (typeof password !== "string" || password.length < 1 || password.length > 128) return null;
    const normalized = this.normalizeEmail(email);
    const account = this.accounts.accounts.find(item => item.email === normalized);
    if (!account || !account.passwordSalt || !account.passwordHash) return null;
    const candidate = crypto.scryptSync(String(password || ""), account.passwordSalt, 64);
    const expected = Buffer.from(account.passwordHash, "hex");
    if (candidate.length !== expected.length || !crypto.timingSafeEqual(candidate, expected)) return null;
    return account;
  }
  createSession(accountId) {
    const now=Date.now();
    const active=[];
    for(const [key,record] of Object.entries(this.sessions)){
      if(!record||record.expiresAt<=now){delete this.sessions[key];continue;}
      if(record.accountId===accountId)active.push(key);
    }
    while(active.length>=10)delete this.sessions[active.shift()];
    while(Object.keys(this.sessions).length>=10000)delete this.sessions[Object.keys(this.sessions)[0]];
    const token = crypto.randomBytes(32).toString("base64url");
    this.sessions[crypto.createHash("sha256").update(token).digest("hex")] = { accountId, createdAt:now, expiresAt: now + SESSION_TTL };
    this.saveSessions();
    return token;
  }
  getSession(token) {
    if (!token) return null;
    const key = crypto.createHash("sha256").update(token).digest("hex");
    const record = this.sessions[key];
    if (!record || record.expiresAt <= Date.now()) {
      if (record) { delete this.sessions[key]; this.saveSessions(); }
      return null;
    }
    const account = this.accounts.accounts.find(item => item.id === record.accountId);
    return account ? { account, discord: account.discord || null, expiresAt: record.expiresAt } : null;
  }
  deleteSession(token) {
    if (!token) return;
    const key = crypto.createHash("sha256").update(token).digest("hex");
    if (this.sessions[key]) { delete this.sessions[key]; this.saveSessions(); }
  }
  createLinkCode(accountId) {
    const now=Date.now();
    for (const [code,item] of Object.entries(this.links)) if(!item||item.expiresAt<=now||item.accountId===accountId)delete this.links[code];
    while(Object.keys(this.links).length>=10000)delete this.links[Object.keys(this.links)[0]];
    let code;
    do { code = String(crypto.randomInt(0, 100000000)).padStart(8, "0"); } while (this.links[code]);
    this.links[code] = { accountId, expiresAt: now + LINK_TTL };
    this.saveLinks();
    return { code, expiresAt: this.links[code].expiresAt };
  }

  createWebToken(accountId) {
    const now = Date.now();
    let activeForAccount=0;
    for (const [key, value] of Object.entries(this.webTokens)) {
      if (!value || value.expiresAt <= now || (value.accountId === accountId && !value.usedAt)) delete this.webTokens[key];
      else if(value.accountId===accountId)activeForAccount++;
    }
    if(activeForAccount>=5)return {error:"Too many server-link tokens were used recently. Wait for an earlier token to expire."};
    const token = crypto.randomBytes(18).toString("base64url");
    const key = crypto.createHash("sha256").update(token).digest("hex");
    this.webTokens[key] = { accountId, createdAt: now, expiresAt: now + WEB_TOKEN_TTL, usedAt: null, guildId: null, guildName: null, userId: null };
    this.saveWebTokens();
    return { token, expiresAt: this.webTokens[key].expiresAt };
  }
  completeWebToken(token, guild, discordUser) {
    const normalized = String(token || "").trim();
    if (normalized.length < 20 || normalized.length > 64 || !/^[A-Za-z0-9_-]+$/.test(normalized)) return { error: "That token is invalid or expired. Generate a new token in the Kimi dashboard." };
    const key = crypto.createHash("sha256").update(normalized).digest("hex");
    const pending = this.webTokens[key];
    const now = Date.now();
    if (!pending || pending.expiresAt <= now || pending.usedAt) return { error: "That token is invalid, expired, or already used. Generate a new token in the Kimi dashboard." };
    const account = this.accounts.accounts.find(item => item.id === pending.accountId);
    if (!account) return { error: "The Kimi account for this token no longer exists." };
    account.guilds = Array.isArray(account.guilds) ? account.guilds : [];
    const linked = { id: guild.id, name: guild.name, linkedBy: discordUser.id, linkedAt: new Date().toISOString() };
    const existing = account.guilds.findIndex(item => item.id === guild.id);
    if (existing >= 0) account.guilds[existing] = linked;
    else account.guilds.push(linked);
    pending.usedAt = now;
    pending.guildId = guild.id;
    pending.guildName = guild.name;
    pending.userId = discordUser.id;
    this.saveAccounts();
    this.saveWebTokens();
    this.logger?.info("A Discord server was linked to a Kimi account.");
    return { guild: linked };
  }
  getWebTokenStatus(accountId, token) {
    const normalized = String(token || "").trim();
    if (!/^[A-Za-z0-9_-]{20,64}$/.test(normalized)) return { status: "invalid" };
    const key = crypto.createHash("sha256").update(normalized).digest("hex");
    const record = this.webTokens[key];
    if (!record || record.accountId !== accountId) return { status: "invalid" };
    if (record.expiresAt <= Date.now()) return { status: "expired" };
    if (!record.usedAt) return { status: "pending", expiresAt: record.expiresAt };
    return { status: "linked", guild: { id: record.guildId, name: record.guildName }, linkedAt: new Date(record.usedAt).toISOString() };
  }
  completeLinkCode(code, discordUser) {
    const normalized = String(code || "").trim();
    const now = Date.now();
    if (!discordUser || !/^\d{15,22}$/.test(String(discordUser.id || ""))) return { error: "The Discord account could not be verified." };
    for (const [userId, record] of this.linkFailures) if (!record || record.resetAt <= now) this.linkFailures.delete(userId);
    if (!this.linkFailures.has(discordUser.id) && this.linkFailures.size >= 5000) this.linkFailures.delete(this.linkFailures.keys().next().value);
    const attempt = this.linkFailures.get(discordUser.id) || { count: 0, resetAt: now + LINK_TTL };
    if (attempt.resetAt <= now) { attempt.count = 0; attempt.resetAt = now + LINK_TTL; }
    if (attempt.count >= 5) return { error: "Too many incorrect linking codes. Wait 10 minutes and generate a new code." };
    const pending = this.links[normalized];
    if (!/^\d{8}$/.test(normalized) || !pending || pending.expiresAt <= now) {
      attempt.count++;
      this.linkFailures.set(discordUser.id, attempt);
      return { error: "That linking code is invalid or expired. Generate a new code in the Kimi dashboard." };
    }
    const account = this.accounts.accounts.find(item => item.id === pending.accountId);
    if (!account) return { error: "Kimi account not found. Sign in again and generate a new code." };
    const linkedElsewhere = this.accounts.accounts.some(item => item.id !== account.id && item.discord?.id === discordUser.id);
    if (linkedElsewhere) return { error: "This Discord account is already linked to another Kimi account." };
    account.discord = { id: discordUser.id, username: discordUser.username, globalName: discordUser.globalName || discordUser.username, avatar: discordUser.avatar || null, linkedAt: new Date().toISOString() };
    delete this.links[normalized];
    this.linkFailures.delete(discordUser.id);
    this.saveAccounts();
    this.saveLinks();
    this.logger?.info("A Discord identity was linked to a Kimi account.");
    return { account: this.publicAccount(account) };
  }
}
