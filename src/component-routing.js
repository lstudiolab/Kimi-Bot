export function pluginForComponent(id=""){
  if(id.startsWith("ticket:"))return "Support";
  if(id.startsWith("modpanel:")||id.startsWith("botguard:")||id.startsWith("verify:"))return "Kimi Lock";
  if(id.startsWith("rolepicker:")||id.startsWith("embed:"))return "Foundation";
  return null;
}

export const libraryForComponent=pluginForComponent;
