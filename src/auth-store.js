import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const SESSION_TTL = 30 * 24 * 60 * 60 * 1000;
const LINK_TTL = 10 * 60 * 1000;

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
    this.accounts = readJson(this.accountsFile, { accounts: [] });
    this.sessions = readJson(this.sessionsFile, {});
    this.links = readJson(this.linksFile, {});
    if (!this.accounts || typeof this.accounts !== "object" || !Array.isArray(this.accounts.accounts)) this.accounts = { accounts: [] };
    if (!this.sessions || typeof this.sessions !== "object" || Array.isArray(this.sessions)) this.sessions = {};
    if (!this.links || typeof this.links !== "object" || Array.isArray(this.links)) this.links = {};
    this.logger = logger;
    this.linkFailures = new Map();
    this.prune();
  }
  saveAccounts() { writeJson(this.accountsFile, this.accounts); }
  saveSessions() { writeJson(this.sessionsFile, this.sessions); }
  saveLinks() { writeJson(this.linksFile, this.links); }
  prune() {
    const now = Date.now();
    let sessionsChanged = false, linksChanged = false;
    for (const [key, value] of Object.entries(this.sessions)) if (!value || value.expiresAt <= now) { delete this.sessions[key]; sessionsChanged = true; }
    for (const [key, value] of Object.entries(this.links)) if (!value || value.expiresAt <= now) { delete this.links[key]; linksChanged = true; }
    if (sessionsChanged) this.saveSessions();
    if (linksChanged) this.saveLinks();
  }
  normalizeEmail(email) { return String(email || "").trim().toLowerCase(); }
  createAccount({ email, password, displayName }) {
    const normalized = this.normalizeEmail(email);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalized) || normalized.length > 254) return { error: "Enter a valid email address." };
    if (String(password || "").length < 10 || String(password).length > 128) return { error: "Password must be between 10 and 128 characters." };
    if (this.accounts.accounts.some(account => account.email === normalized)) return { error: "An account with this email already exists." };
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
    const token = crypto.randomBytes(32).toString("base64url");
    this.sessions[crypto.createHash("sha256").update(token).digest("hex")] = { accountId, expiresAt: Date.now() + SESSION_TTL };
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
    for (const [code, item] of Object.entries(this.links)) if (!item || item.expiresAt <= Date.now()) delete this.links[code];
    let code;
    do { code = String(crypto.randomInt(0, 100000000)).padStart(8, "0"); } while (this.links[code]);
    this.links[code] = { accountId, expiresAt: Date.now() + LINK_TTL };
    this.saveLinks();
    return { code, expiresAt: this.links[code].expiresAt };
  }
  completeLinkCode(code, discordUser) {
    const normalized = String(code || "").trim();
    const now = Date.now();
    for (const [userId, record] of this.linkFailures) if (record.resetAt <= now) this.linkFailures.delete(userId);
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
