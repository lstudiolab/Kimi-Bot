export function libraryForComponent(id=""){
  if(id.startsWith("ticket:"))return "Support";
  if(id.startsWith("modpanel:")||id.startsWith("botguard:")||id.startsWith("verify:"))return "Security";
  if(id.startsWith("rolepicker:")||id.startsWith("embed:"))return "Foundation";
  if(id.startsWith("tbs:")||id.startsWith("tbm:")||id.startsWith("tbm-submit:")||id.startsWith("developer:"))return "Scratch";
  return null;
}
