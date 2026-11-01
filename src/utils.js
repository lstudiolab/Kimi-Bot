export const DAY = 86_400_000;

export function fillDefaults(target, source) {
  for (const [key, value] of Object.entries(source)) {
    if (target[key] === undefined) target[key] = structuredClone(value);
  }
  return target;
}
export function isSnowflake(value) { return /^\d{15,22}$/.test(String(value ?? "")); }
export function trim(value) { return String(value ?? "").trim(); }
export function nowMs() { return Date.now(); }
export function snowflakeTime(id) {
  try { return Number((BigInt(String(id)) >> 22n) + 1420070400000n); }
  catch { return Date.now(); }
}
export function normalizeMessage(value) {
  return String(value ?? "").toLowerCase()
    .replace(/https?:\/\/\S+/g, " url ")
    .replace(/<@!?\d+>|<@&\d+>|<#\d+>/g, " mention ")
    .replace(/[\p{P}\p{C}]/gu, " ").replace(/\s+/g, " ").trim();
}
export function matchesBlockedPhrase(content,phrase){
  const haystack=String(content||"").toLowerCase().replace(/\s+/g," ");
  const needle=String(phrase||"").trim().toLowerCase().replace(/\s+/g," ");
  if(!needle)return false;
  const codepoints=Array.from(needle),isWord=character=>Boolean(character&&/[\p{L}\p{N}_]/u.test(character));
  const leftBoundary=isWord(codepoints[0]),rightBoundary=isWord(codepoints.at(-1));
  let index=haystack.indexOf(needle);
  while(index!==-1){
    const before=Array.from(haystack.slice(0,index)).at(-1);
    const after=Array.from(haystack.slice(index+needle.length))[0];
    if((!leftBoundary||!isWord(before))&&(!rightBoundary||!isWord(after)))return true;
    index=haystack.indexOf(needle,index+1);
  }
  return false;
}
export function jaccard(leftText, rightText) {
  const left = new Set(normalizeMessage(leftText).split(/\s+/).filter(Boolean));
  const right = new Set(normalizeMessage(rightText).split(/\s+/).filter(Boolean));
  if (!left.size && !right.size) return 0;
  let intersection = 0;
  for (const word of left) if (right.has(word)) intersection++;
  return intersection / (left.size + right.size - intersection);
}
export function cleanChannelName(value) {
  return String(value || "ticket").toLowerCase().replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-").replace(/^-|-$/g, "").slice(0, 90) || "ticket";
}
export function mentionChannel(id) { return id ? `<#${id}>` : "Not configured"; }
export function mentionRole(id) { return id ? `<@&${id}>` : "Not configured"; }
export function chunkText(text, max = 1900) {
  const limit=Math.max(1,Math.floor(Number(max)||1900));
  const chunks=[];
  let current="";
  for(const line of String(text).split("\n")){
    if(line.length===0){
      if(current.length<limit)current+=(current?"\n":"");
      else if(current){chunks.push(current);current="";}
      continue;
    }
    let offset=0;
    while(offset<line.length){
      const separator=current?"\n":"";
      const room=limit-current.length-separator.length;
      if(room<=0){chunks.push(current);current="";continue;}
      const part=line.slice(offset,offset+room);
      current+=separator+part;
      offset+=part.length;
      if(offset<line.length){chunks.push(current);current="";}
    }
  }
  if(current)chunks.push(current);
  return chunks;
}
export function hasManager(interaction) {
  return interaction.memberPermissions?.has("ManageGuild") ?? false;
}
export function isOwner(member) {
  return Boolean(member?.guild?.ownerId && member.id === member.guild.ownerId);
}


// Resolve template placeholders consistently in greetings and saved embeds.
// Unknown placeholders remain untouched so configuration mistakes are visible.
export function renderTemplate(template, context = {}) {
  const guild = context.guild || context.member?.guild || null;
  const member = context.member || null;
  const user = context.user || member?.user || null;
  const channel = context.channel || null;
  const botUser = context.client?.user || context.bot || null;
  const avatar = user?.displayAvatarURL
    ? user.displayAvatarURL({ extension: "png", size: 256 })
    : null;
  const botAvatar = botUser?.displayAvatarURL
    ? botUser.displayAvatarURL({ extension: "png", size: 256 })
    : null;
  const values = {
    user: user?.id ? `<@${user.id}>` : null,
    member: user?.id ? `<@${user.id}>` : null,
    user_mention: user?.id ? `<@${user.id}>` : null,
    username: user?.username ?? null,
    member_name: user?.globalName ?? user?.username ?? null,
    user_name: user?.globalName ?? user?.username ?? null,
    user_tag: user?.tag ?? (user?.username && user?.discriminator && user.discriminator !== "0" ? `${user.username}#${user.discriminator}` : user?.username ?? null),
    user_id: user?.id ?? null,
    member_id: user?.id ?? null,
    user_avatar: avatar,
    server: guild?.name ?? null,
    server_name: guild?.name ?? null,
    server_id: guild?.id ?? null,
    server_icon: guild?.iconURL?.({ extension: "png", size: 256 }) ?? null,
    member_count: guild?.memberCount ?? null,
    channel: channel?.id ? `<#${channel.id}>` : null,
    channel_mention: channel?.id ? `<#${channel.id}>` : null,
    channel_name: channel?.name ?? null,
    owner: guild?.ownerId ? `<@${guild.ownerId}>` : null,
    server_owner: guild?.ownerId ? `<@${guild.ownerId}>` : null,
    owner_id: guild?.ownerId ?? null,
    server_owner_id: guild?.ownerId ?? null,
    bot: botUser?.id ? `<@${botUser.id}>` : null,
    bot_mention: botUser?.id ? `<@${botUser.id}>` : null,
    bot_name: botUser?.username ?? null,
    bot_avatar: botAvatar,
    date: new Date().toLocaleDateString("en-GB", { timeZone: "UTC" }),
    time: new Date().toLocaleTimeString("en-GB", { timeZone: "UTC" }),
    timestamp: Math.floor(Date.now() / 1000)
  };
  return String(template ?? "").replace(/\{\s*([a-z][a-z0-9_-]*)\s*\}/gi, (match, key) => {
    const normalized = key.toLowerCase().replace(/-/g, "_");
    const value = values[normalized];
    return value === null || value === undefined ? match : String(value);
  });
}


const URL_TEMPLATE_PLACEHOLDERS = Object.freeze({
  "user-avatar": "https://cdn.example/user-avatar.png",
  "server-icon": "https://cdn.example/server-icon.png",
  "bot-avatar": "https://cdn.example/bot-avatar.png"
});

export function isHttpsUrlTemplate(value) {
  const input=String(value ?? "").trim();
  if(!input)return true;
  const candidate=input.replace(/\{\s*([a-z][a-z0-9_-]*)\s*\}/gi,(match,key)=>{
    const normalized=key.toLowerCase().replace(/_/g,"-");
    return URL_TEMPLATE_PLACEHOLDERS[normalized] || match;
  });
  if(/[{}]/.test(candidate))return false;
  try {
    const parsed=new URL(candidate);
    return parsed.protocol==="https:" && Boolean(parsed.hostname);
  } catch {
    return false;
  }
}

export const TEMPLATE_PLACEHOLDERS = Object.freeze([
  "{user}", "{member}", "{user-mention}", "{username}", "{member-name}", "{user-name}",
  "{user_tag}", "{user_id}", "{member-id}", "{user-avatar}", "{server}", "{server-name}",
  "{server_id}", "{server-icon}", "{member_count}", "{member-count}", "{channel}",
  "{channel-mention}", "{channel_name}", "{channel-name}", "{owner}", "{server-owner}",
  "{owner_id}", "{server-owner-id}", "{bot}", "{bot-mention}", "{bot_name}", "{bot-avatar}",
  "{date}", "{time}", "{timestamp}"
]);
