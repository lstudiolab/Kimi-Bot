import { PermissionFlagsBits as P } from "discord.js";

export const SELF_SERVICE_BLOCKED_PERMISSIONS=Object.freeze([
  P.Administrator,
  P.ManageGuild,
  P.ManageRoles,
  P.ManageChannels,
  P.ManageWebhooks,
  P.BanMembers,
  P.KickMembers,
  P.ModerateMembers,
  P.ManageMessages,
  P.ManageNicknames,
  P.MentionEveryone
]);

export function isSafeAssignableRole(role,guildId){
  if(!role||role.id===guildId||role.managed)return false;
  return !SELF_SERVICE_BLOCKED_PERMISSIONS.some(permission=>role.permissions?.has(permission));
}
