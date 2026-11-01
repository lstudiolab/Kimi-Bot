const statusNode=document.querySelector("#verify-status");
const login=document.querySelector("#discord-login");
const logout=document.querySelector("#discord-logout");
const errors={
 "oauth-not-configured":"Discord sign-in is not configured on this Kimi host.",
 "discord-denied":"Discord authorization was cancelled. You can try again.",
 "invalid-session":"This sign-in link expired or was opened in another browser. Start again.",
 "oauth-failed":"Discord could not complete sign-in. Please try again.",
 "profile-failed":"Kimi could not retrieve your Discord profile."
};
const error=new URLSearchParams(location.search).get("error");
function showError(message){statusNode.textContent=message;statusNode.classList.add("error");}
if(error)showError(errors[error]||"Sign-in could not be completed. Please try again.");
fetch("/api/me",{credentials:"same-origin",cache:"no-store"})
 .then(async response=>{if(!response.ok)throw new Error("not-signed-in");return response.json();})
 .then(({user})=>{
  statusNode.replaceChildren();
  const line=document.createElement("div");line.className="verified-user";
  const avatar=document.createElement("span");avatar.className="avatar";
  if(user.avatar){const img=document.createElement("img");img.src="https://cdn.discordapp.com/avatars/"+encodeURIComponent(user.id)+"/"+encodeURIComponent(user.avatar)+".png?size=64";img.alt="";avatar.append(img);}
  else avatar.textContent="D";
  const copy=document.createElement("span");copy.textContent=user.globalName||user.username;
  line.append(avatar,copy);statusNode.append(line);
  const success=document.createElement("p");success.textContent="You're signed in. Your dashboard is ready.";statusNode.append(success);
  login.textContent="Open Kimi dashboard";login.href="/";logout.hidden=false;
 })
 .catch(()=>{if(!error)statusNode.textContent="Sign in to continue to your dashboard.";});
logout.addEventListener("click",async()=>{
 logout.disabled=true;
 try{await fetch("/auth/logout",{method:"POST",credentials:"same-origin"});}
 finally{location.reload();}
});
