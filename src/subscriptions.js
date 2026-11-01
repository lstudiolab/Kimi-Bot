const MIB = 1024 * 1024;

export const PLANS = Object.freeze({
  free: Object.freeze({ name: "Timi Free", storageBytes: 5 * MIB, storageLabel: "5 MB", priceMonthly: 0, priceAnnual: 0 })
});

const STORAGE_COLLECTIONS = Object.freeze([
  "installed_libraries", "welcome", "tickets", "moderation", "verification",
  "developer_projects", "developer_history", "developer_redo", "panel_scripts",
  "customizations", "library_data", "timi_setup", "automod_words", "moderation_cases", "moderation_jobs", "pending_bots", "developer_active"
]);

export function getPlanForData(_data, _guildId) { return "free"; }
export function getGuildPlan(_store, _guildId) { return "free"; }

function guildStorageSnapshot(data, guildId, overrides = {}) {
  const snapshot = {};
  for (const collection of STORAGE_COLLECTIONS) {
    const source = overrides[collection] ?? data[collection] ?? {};
    if (source && Object.prototype.hasOwnProperty.call(source, guildId)) snapshot[collection] = source[guildId];
  }
  for (const collection of ["role_picker_menus", "role_picker_drafts"]) {
    const source = overrides[collection] ?? data[collection] ?? {};
    const selected = {};
    for (const [key, value] of Object.entries(source)) if (value?.guild_id === guildId) selected[key] = value;
    if (Object.keys(selected).length) snapshot[collection] = selected;
  }
  for (const collection of ["embeds", "members", "pending_bots"]) {
    const selected = {};
    for (const [key, value] of Object.entries(data[collection] || {})) if (key.startsWith(guildId + ":")) selected[key] = value;
    if (Object.keys(selected).length) snapshot[collection] = selected;
  }
  return snapshot;
}

export function getGuildStorageBytes(data, guildId) {
  return Buffer.byteLength(JSON.stringify(guildStorageSnapshot(data, guildId)), "utf8");
}

export function restoreGuildStorage(target, source, guildId) {
  for (const collection of STORAGE_COLLECTIONS) {
    target[collection] ||= {};
    if (source[collection] && Object.prototype.hasOwnProperty.call(source[collection], guildId)) target[collection][guildId] = structuredClone(source[collection][guildId]);
    else delete target[collection][guildId];
  }
  for (const collection of ["role_picker_menus", "role_picker_drafts"]) {
    target[collection] ||= {};
    for (const [key, value] of Object.entries(target[collection])) if (value?.guild_id === guildId) delete target[collection][key];
    for (const [key, value] of Object.entries(source[collection] || {})) if (value?.guild_id === guildId) target[collection][key] = structuredClone(value);
  }
  for (const collection of ["embeds", "members"]) {
    target[collection] ||= {};
    for (const key of Object.keys(target[collection])) if (key.startsWith(guildId + ":")) delete target[collection][key];
    for (const [key, value] of Object.entries(source[collection] || {})) if (key.startsWith(guildId + ":")) target[collection][key] = structuredClone(value);
  }
}

export function getStorageReport(store, guildId) {
  const bytes = getGuildStorageBytes(store.data, guildId), limit = PLANS.free.storageBytes;
  return { tier: "free", bytes, limit, remaining: Math.max(0, limit - bytes), percent: Math.min(100, Math.round(bytes / limit * 100)), exceeded: bytes > limit };
}

export function canStoreGuildState(store, guildId, overrides = {}) {
  const bytes = getGuildStorageBytes({ ...store.data, ...overrides }, guildId);
  return { ok: bytes <= PLANS.free.storageBytes, bytes, limit: PLANS.free.storageBytes, tier: "free" };
}

export function formatBytes(value) {
  const bytes = Math.max(0, Number(value) || 0);
  if (bytes < 1024) return bytes + " B";
  if (bytes < MIB) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / MIB).toFixed(2) + " MB";
}
