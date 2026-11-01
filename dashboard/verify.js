const form=document.querySelector("#auth-form");
const statusNode=document.querySelector("#verify-status");
const title=document.querySelector("#auth-title");
const submit=document.querySelector("#auth-submit");
const displayNameField=document.querySelector("#display-name-field");
let mode="login";
function showStatus(message,error=false){statusNode.textContent=message;statusNode.classList.toggle("error",error);}
function setMode(next){
 mode=next;
 document.querySelectorAll("[data-mode]").forEach(button=>button.classList.toggle("active",button.dataset.mode===mode));
 displayNameField.hidden=mode!=="register";
 form.elements.password.autocomplete=mode==="register"?"new-password":"current-password";
 form.elements.password.minLength=mode==="register"?10:1;
 form.elements.password.placeholder=mode==="register"?"At least 10 characters":"Your password";
 submit.innerHTML=mode==="register"?"Create account <span aria-hidden=\"true\">↗</span>":"Sign in <span aria-hidden=\"true\">↗</span>";
 title.innerHTML=mode==="register"?"Create your<br>Kimi account.":"Your server.<br>Under control.";
 showStatus(mode==="register"?"Create an account to get started.":"Sign in with your Kimi email and password.");
}
document.querySelectorAll("[data-mode]").forEach(button=>button.addEventListener("click",()=>setMode(button.dataset.mode)));
fetch("/api/me",{credentials:"same-origin",cache:"no-store"}).then(response=>{if(response.ok)location.replace("/");}).catch(()=>{});
form.addEventListener("submit",async event=>{
 event.preventDefault();
 submit.disabled=true;
 showStatus(mode==="register"?"Creating your Kimi account…":"Signing in…");
 const payload={email:form.elements.email.value,password:form.elements.password.value,displayName:form.elements.displayName.value};
 try{
  const response=await fetch(mode==="register"?"/auth/register":"/auth/login",{method:"POST",credentials:"same-origin",headers:{"Content-Type":"application/json"},body:JSON.stringify(payload)});
  const result=await response.json().catch(()=>({}));
  if(!response.ok)throw new Error(result.error||"Authentication failed.");
  location.replace("/");
 }catch(error){showStatus(error.message,true);}
 finally{submit.disabled=false;}
});
