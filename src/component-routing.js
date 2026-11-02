export function pluginForComponent(id=""){
  if(id.startsWith("ticket:"))return "Support";
  if(id.startsWith("modpanel:")||id.startsWith("botguard:")||id.startsWith("verify:"))return "Kimi Lock";
  if(id.startsWith("rolepicker:"))return "Role Picker";
  if(id.startsWith("embed:"))return "Embeds";
  return null;
}

export const libraryForComponent=pluginForComponent;
