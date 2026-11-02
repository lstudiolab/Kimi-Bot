import { PermissionFlagsBits as P } from "discord.js";

const BLOCKED_PERMISSION_NAMES=Object.freeze([
  "Administrator",
  "ManageGuild",
  "ManageRoles",
  "ManageChannels",
  "ManageWebhooks",
  "ManageGuildExpressions",
  "ManageEmojisAndStickers",
  "ManageSoundboard",
  "ManageGuildScheduledEvents",
  "CreateInstantInvite",
  "ManageEvents",
  "ManageThreads",
  "ManageMessages",
  "ManageNicknames",
  "KickMembers",
  "BanMembers",
  "ModerateMembers",
  "ViewAuditLog",
  "MentionEveryone",
  "MuteMembers",
  "DeafenMembers",
  "MoveMembers"
]);

export const SELF_SERVICE_BLOCKED_PERMISSIONS=Object.freeze([
  ...new Set(BLOCKED_PERMISSION_NAMES.map(name=>P[name]).filter(value=>typeof value==="bigint"))
]);

export function isSafeAssignableRole(role,guildId){
  if(!role||role.id===guildId||role.managed)return false;
  return !SELF_SERVICE_BLOCKED_PERMISSIONS.some(permission=>role.permissions?.has(permission));
}
