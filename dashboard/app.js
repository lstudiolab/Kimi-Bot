const $ = (selector, root=document) => root.querySelector(selector);
const $$ = (selector, root=document) => Array.from(root.querySelectorAll(selector));
const pageNames = {
overview:"Overview",welcome:"Welcome message",goodbye:"Goodbye message",autorole:"Automatic roles",
"role-panels":"Role panels","role-settings":"Role settings","embed-editor":"Embed editor","saved-embeds":"Saved embeds",
automod:"AutoMod",verification:"Verification","anti-raid":"Anti-raid","anti-nuke":"Anti-nuke","bot-approval":"Bot approval",
"image-checks":"Image checks","moderation-cases":"Warnings & cases",recovery:"Recovery","security-audit":"Security audit",
"ticket-setup":"Ticket setup","ticket-panel":"Ticket panel","ticket-settings":"Ticket settings","ticket-history":"Ticket history",
projects:"Projects","script-editor":"TbScript editor","script-templates":"Templates & kit","script-history":"Version history",
"script-import":"Import & export","server-settings":"Server settings",permissions:"Permissions"
};
const descriptions = {
welcome:"Control the first message members see when they join your server.",
goodbye:"Choose where and how Timi announces member departures.",
autorole:"Assign selected roles automatically when a member joins.",
"role-panels":"Create and publish self-service role selection panels.",
"role-settings":"Set role picker behavior and assignment limits.",
"embed-editor":"Build reusable Discord embeds with a live preview.",
"saved-embeds":"Manage embeds saved for this server.",
automod:"Configure spam detection, message filters and automatic actions.",
verification:"Set account-age requirements, scoring and manual review.",
"anti-raid":"Configure join-burst detection and raid containment.",
"anti-nuke":"Monitor destructive administrative actions and suspicious changes.",
"bot-approval":"Review new bots before allowing them full server access.",
"image-checks":"Inspect image metadata, OCR text, QR codes and suspicious URLs.",
"moderation-cases":"Review warnings, moderation actions and case history.",
recovery:"Manage channel snapshots and bounded message recovery.",
"security-audit":"Review server configuration and permission risks.",
"ticket-setup":"Prepare the private ticket category and support channels.",
"ticket-panel":"Customize and publish the ticket opening panel.",
"ticket-settings":"Configure support roles, transcripts and ticket behavior.",
"ticket-history":"Review ticket activity and transcript records.",
projects:"Browse your TbScript projects.",
"script-editor":"Write and validate restricted TbScript projects.",
"script-templates":"Start from a panel, button, ticket or welcome template.",
"script-history":"Review project versions and restore earlier work.",
"script-import":"Import or export .tdl project files.",
"server-settings":"Set server-wide dashboard preferences.",
permissions:"Review which server roles can manage Timi."
};
const moduleMap = {
welcome:["welcome","goodbye","autorole"],roles:["role-panels","role-settings"],embeds:["embed-editor","saved-embeds"],
security:["automod","verification","anti-raid","anti-nuke","bot-approval","image-checks","moderation-cases","recovery","security-audit"],
tickets:["ticket-setup","ticket-panel","ticket-settings","ticket-history"],
developer:["projects","script-editor","script-templates","script-history","script-import"]
};
const symbols = {welcome:"⌂",roles:"◇",embeds:"▤",security:"⬡",tickets:"▱",developer:"⌘"};
const moduleTitles = {welcome:"Welcome & Goodbye",roles:"Role Picker",embeds:"Embed Builder",security:"Moderation & Security",tickets:"Ticket System",developer:"Developer"};
const moduleForPage = {};
Object.keys(moduleMap).forEach(key=>moduleMap[key].forEach(page=>moduleForPage[page]=key));
const defaults = {
welcome:{enabled:true,channel:"",title:"Welcome to {server}",message:"Welcome {user}. We are glad you are here.",image:"",mention:true},
goodbye:{enabled:false,channel:"",message:"{user} has left {server}.",image:""},
autorole:{enabled:false,role:"",delay:"0"},
"role-panels":{enabled:false,title:"Choose your roles",description:"Select the roles you would like to receive.",style:"buttons"},
"role-settings":{single:false,remove:true,allowMultiple:true},
"embed-editor":{title:"Welcome",description:"Thanks for joining our community.",color:"#808080",footer:"Timi"},
automod:{enabled:false,threshold:"20",window:"60",sanction:"timeout",duration:"10",logChannel:"",invites:true,mentions:true,caps:true,links:false},
verification:{enabled:false,minAge:"7",passScore:"80",reviewScore:"60",verifiedRole:"",reviewChannel:""},
"anti-raid":{enabled:true,joinThreshold:"8",window:"10",timeout:"10"},
"anti-nuke":{enabled:true,actionThreshold:"3",window:"60",timeout:"60",logChannel:""},
"bot-approval":{enabled:true,channel:"",restrict:true},
"image-checks":{enabled:true,maxSize:"8",ocr:true,qr:true,duplicate:true,urlChecks:true},
"moderation-cases":{enabled:true,retention:"30",logChannel:""},
recovery:{enabled:true,storage:"5",retention:"7",messages:true,channels:true},
"security-audit":{enabled:true,logChannel:""},
"ticket-setup":{enabled:false,category:"ticket",logChannel:"",supportRole:""},
"ticket-panel":{enabled:false,title:"Contact support",description:"Open a ticket and our team will help you.",button:"Open Ticket",channel:""},
"ticket-settings":{supportRole:"",transcriptChannel:"",maxMessages:"1000",closeDelay:"5",staffThread:true},
"script-editor":{name:"welcome-panel",source:'panel:\n    title "Welcome"\n    description "Welcome to our server."\n    color "#808080"\n    button "Get Started" : start\n\nonclick start:\n    reply "Welcome!"\nend'},
"server-settings":{language:"en-US",timezone:"Asia/Manila",prefix:"/",embedColor:"#808080"},
permissions:{managerRole:"",ownerOnly:true}
};
const state = loadState();
function loadState(){try{return Object.assign({},defaults,JSON.parse(localStorage.getItem("timi-dashboard-state")||"{}"));}catch{return {...defaults};}}
function saveState(){localStorage.setItem("timi-dashboard-state",JSON.stringify(state));}
function esc(value){return String(value??"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]));}
function toast(message){const node=document.createElement("div");node.className="toast";node.textContent=message;$("#toast-region").append(node);setTimeout(()=>node.remove(),2800);}
function field(key,label,type="text",help="",placeholder=""){const value=(state[currentPage]||{})[key]??"";return '<div class="field"><label for="f-'+key+'">'+label+'</label><input id="f-'+key+'" name="'+key+'" type="'+type+'" value="'+esc(value)+'" placeholder="'+esc(placeholder)+'">'+(help?'<small class="field-help">'+help+'</small>':"")+'</div>';}
function area(key,label,help=""){const value=(state[currentPage]||{})[key]??"";return '<div class="field"><label for="f-'+key+'">'+label+'</label><textarea id="f-'+key+'" name="'+key+'">'+esc(value)+'</textarea>'+(help?'<small class="field-help">'+help+'</small>':"")+'</div>';}
function selectField(key,label,options){const value=(state[currentPage]||{})[key]??"";return '<div class="field"><label for="f-'+key+'">'+label+'</label><select id="f-'+key+'" name="'+key+'">'+options.map(o=>'<option value="'+esc(o[0])+'" '+(value===o[0]?"selected":"")+'>'+esc(o[1])+'</option>').join("")+'</select></div>';}
function toggle(key,label,help=""){const value=(state[currentPage]||{})[key]===true;return '<div class="toggle-row"><div class="toggle-copy"><strong>'+label+'</strong>'+(help?'<small>'+help+'</small>':"")+'</div><input class="switch" type="checkbox" name="'+key+'" '+(value?"checked":"")+'></div>';}
function card(title,body,subtitle=""){return '<section class="card"><div class="card-header"><div><h2 class="card-title">'+title+'</h2>'+(subtitle?'<div class="card-subtitle">'+subtitle+'</div>':"")+'</div></div>'+body+'</section>';}
function heading(page,actions=""){const mod=moduleForPage[page];return '<div class="page-heading"><div><div class="eyebrow">'+(mod?moduleTitles[mod]:"Workspace")+'</div><h1>'+pageNames[page]+'</h1><p>'+ (descriptions[page]||"Manage your Timi dashboard.")+'</p></div><div class="heading-actions">'+actions+'</div></div>';}
function saveButton(){return '<button class="button" type="submit">Save changes</button>';}
let currentPage="overview";
function navigate(page){if(!pageNames[page])page="overview";location.hash=page;}
function setActive(page){$$(".nav-item").forEach(a=>a.classList.toggle("active",a.dataset.page===page));const group=moduleForPage[page];if(group){const parent=$('[data-children="'+group+'"]');if(parent)parent.closest(".nav-group").classList.remove("collapsed");}$("#crumb-current").textContent=pageNames[page]||"Overview";}
function renderOverview(){
const systems=Object.keys(moduleMap).flatMap(group=>moduleMap[group].map(page=>({page,group})));
const active=systems.filter(x=>state[x.page]?.enabled===true).length;
const moduleRows=Object.keys(moduleMap).map(group=>'<div class="system-row"><div class="system-symbol">'+symbols[group]+'</div><div class="system-copy"><strong>'+moduleTitles[group]+'</strong><small>'+moduleMap[group].length+' systems · '+moduleMap[group].map(p=>pageNames[p]).join(", ")+'</small></div><span class="status">Available</span></div>').join("");
return heading("overview",'<button class="button secondary" data-action="refresh">Refresh</button>')+
'<div class="grid stats-grid"><div class="stat-card"><div class="stat-top">Modules <span class="stat-icon">▦</span></div><div class="stat-value">6</div><div class="stat-note">Your six Timi modules</div></div><div class="stat-card"><div class="stat-top">Systems <span class="stat-icon">⌘</span></div><div class="stat-value">'+systems.length+'</div><div class="stat-note">Pages available in this dashboard</div></div><div class="stat-card"><div class="stat-top">Enabled in preview <span class="stat-icon">◉</span></div><div class="stat-value">'+active+'</div><div class="stat-note">Browser-side preview values</div></div><div class="stat-card"><div class="stat-top">Connection <span class="stat-icon">↗</span></div><div class="stat-value" style="font-size:17px;margin-top:17px">Not connected</div><div class="stat-note">Termux API bridge not configured</div></div></div>'+
'<div class="grid overview-grid"><div>'+card("Your modules",'<div class="system-list">'+moduleRows+'</div>',"All six modules are available in the navigation.")+card("Activity overview",'<div class="chart-bars"><span style="height:28%"></span><span style="height:46%"></span><span style="height:39%"></span><span style="height:65%"></span><span style="height:51%"></span><span style="height:79%"></span><span style="height:58%"></span><span style="height:91%"></span></div><div class="chart-labels"><span>Mon</span><span>Tue</span><span>Wed</span><span>Thu</span><span>Fri</span><span>Sat</span><span>Sun</span><span>Today</span></div><p class="empty-note">Illustrative preview only. Live Discord activity will appear after the dashboard API is connected.</p>',"Preview chart")+'</div><div>'+card("Quick access",'<div class="grid quick-grid">'+[['automod','AutoMod'],['verification','Verification'],['ticket-panel','Ticket panel'],['script-editor','TbScript editor'],['welcome','Welcome message'],['embed-editor','Embed builder']].map(x=>'<a class="quick-link" href="#'+x[0]+'"><strong>'+x[1]+'</strong><small>Open settings →</small></a>').join("")+'</div>')+card("Connection status",'<div class="notice info">This is a static frontend preview. Changes are stored in this browser and are not yet sent to your Discord bot.</div><div class="toggle-row"><div class="toggle-copy"><strong>GitHub Pages frontend</strong><small>Static dashboard files</small></div><span class="status">Ready</span></div><div class="toggle-row"><div class="toggle-copy"><strong>Termux API</strong><small>Secure bot settings bridge</small></div><span class="status off">Not configured</span></div>')+'</div></div>';
}
function renderFormPage(page){
const cfg=state[page]||{};
let main="",side="";
if(["welcome","goodbye"].includes(page)){
main=card("Message configuration",toggle("enabled","Enable "+(page==="welcome"?"welcome":"goodbye")+" messages","Turn this system on or off.")+field("channel","Destination channel","text","Discord channel ID or #channel name.")+field("title","Message title","text","Use {server} and {user} placeholders.")+area("message","Message content","Supported placeholders: {user}, {server}, {memberCount}.")+field("image","Image URL","url","Optional image shown with the message.")+toggle("mention","Mention the member","Allow Timi to mention the joining member."), "Customize the message sent by Timi.")+card("Preview",'<div class="preview-box"><strong>'+(esc(cfg.title||"Welcome to {server}").replaceAll("{server}","Your server"))+'</strong><p>'+esc(cfg.message||"Your message preview appears here.").replaceAll("{user}","@Member").replaceAll("{server}","Your server")+'</p><small class="muted">Preview · Discord message</small></div>');
side=card("How it works",'<p class="empty-note">Timi listens for member join and leave events, then posts the configured message to the selected channel. The bot needs permission to view and send messages in that channel.</p>');
}else if(page==="autorole"){
main=card("Automatic role assignment",toggle("enabled","Enable automatic roles","Assign roles to new members.")+field("role","Role ID or role name","text","The role Timi should assign.")+selectField("delay","Assignment timing",[["0","Immediately"],["5","After 5 seconds"],["30","After 30 seconds"],["60","After 1 minute"]]),"New member behavior");
side=card("Requirements",'<p class="empty-note">Timi needs Manage Roles. Its highest role must be above the role being assigned. Managed roles and @everyone cannot be assigned.</p>');
}else if(page==="role-panels"){
main=card("Role panel",toggle("enabled","Enable role panel","Allow members to select roles.")+field("title","Panel title")+area("description","Description")+selectField("style","Panel style",[["buttons","Buttons"],["select","Dropdown menu"]]),"Panel content")+card("Role options",'<div class="notice info">Role choices are loaded from Discord when the dashboard API is connected. This preview lets you configure the panel layout only.</div><button class="button secondary" data-action="add-role">Add role option</button><div id="role-options" class="empty-state">No role options added in this preview.</div>');
side=card("Publishing",'<p class="empty-note">A published panel stays active in Discord. Members can use it without dashboard access. Timi must have Manage Roles and a role position above the selectable roles.</p>');
}else if(page==="role-settings"){
main=card("Selection behavior",toggle("single","Allow only one selected role","Selecting a new role removes the previous selection.")+toggle("remove","Allow members to remove roles","Members can toggle an assigned role off.")+toggle("allowMultiple","Allow multiple role selections","Members may select more than one role."),"Role picker rules");
side=card("Safety",'<p class="empty-note">Timi should only expose safe, self-assignable roles. Administrator, managed and higher-position roles must be excluded.</p>');
}else if(page==="embed-editor"){
main=card("Embed content",field("title","Title")+area("description","Description")+field("color","Accent color","color")+field("footer","Footer text")+field("image","Image URL","url"),"Build your embed")+card("Discord preview",'<div class="preview-box" id="embed-preview" style="border-left-color:'+esc(cfg.color||"#808080")+'"><strong>'+esc(cfg.title||"Embed title")+'</strong><p>'+esc(cfg.description||"Your embed description will appear here.")+'</p><small class="muted">'+esc(cfg.footer||"Footer")+'</small></div>');
side=card("Embed tools",'<button class="button secondary" data-action="save-embed">Save embed</button> <button class="button secondary" data-action="post-embed">Publish preview</button><div class="divider"></div><p class="empty-note">Discord embed limits apply: title 256 characters, description 4,096 characters and up to 25 fields.</p>');
}else if(page==="automod"){
main=card("Automatic moderation",toggle("enabled","Enable AutoMod","Scan messages for configured spam and rule violations.")+field("threshold","Message threshold","number","Messages allowed within the time window.")+field("window","Time window (seconds)","number")+selectField("sanction","Default action",[["delete","Delete message"],["timeout","Timeout member"],["kick","Kick member"],["ban","Ban member"]])+field("duration","Timeout duration (minutes)","number")+field("logChannel","Log channel","text","Channel ID or channel name.") ,"Core controls")+card("Detection rules",toggle("invites","Block Discord invite links")+toggle("mentions","Block mass mentions")+toggle("caps","Detect excessive capitalization")+toggle("links","Detect repeated links"));
side=card("Moderation notes",'<div class="notice">Start with message deletion or short timeouts. Review false positives before enabling stronger sanctions.</div><p class="empty-note">The current bot implementation supports message bursts, repeated messages, invite links, mass mentions, excessive caps, link spam and blocked phrases.</p>');
}else if(page==="verification"){
main=card("Verification settings",toggle("enabled","Enable verification","Require members to complete the verification panel.")+field("minAge","Minimum account age (days)","number")+field("passScore","Automatic pass score","number")+field("reviewScore","Manual review score","number")+field("verifiedRole","Verified role ID","text")+field("reviewChannel","Review channel ID","text"),"Member verification")+card("Scoring behavior",'<div class="toggle-row"><div class="toggle-copy"><strong>Automatic approval</strong><small>Members meeting the pass threshold receive the verified role.</small></div><span class="pill">80+ default</span></div><div class="toggle-row"><div class="toggle-copy"><strong>Manual review</strong><small>Borderline scores are sent to the review channel.</small></div><span class="pill">60–79 default</span></div><div class="toggle-row"><div class="toggle-copy"><strong>Low score handling</strong><small>Scores below the review range trigger a kick attempt.</small></div><span class="pill">Below 60</span></div>');
side=card("Review queue",'<div class="empty-state"><strong>No review records in preview</strong>Connect the API to view pending verification decisions.</div>');
}else if(page==="anti-raid"){
main=card("Raid detection",toggle("enabled","Enable raid containment","Watch rapid member joins.")+field("joinThreshold","Join threshold","number","Number of joins that trigger containment.")+field("window","Detection window (seconds)","number")+field("timeout","Containment timeout (minutes)","number"),"Join burst controls");
side=card("Current behavior",'<p class="empty-note">The bot currently warns on six joins in ten seconds and starts a 60-second containment window at eight joins in ten seconds. Manageable non-administrator accounts may receive a 10-minute timeout.</p>');
}else if(page==="anti-nuke"){
main=card("Destructive action monitoring",toggle("enabled","Enable anti-nuke monitoring")+field("actionThreshold","Action threshold","number","Repeated sensitive actions before intervention.")+field("window","Monitoring window (seconds)","number")+field("timeout","Timeout duration (minutes)","number")+field("logChannel","Security log channel","text"),"Audit event protection");
side=card("Monitored activity",'<p class="empty-note">Sensitive audit activity includes destructive channel, role, webhook, permission and member-role changes. Role hierarchy and Discord permissions limit possible interventions.</p>');
}else if(page==="bot-approval"){
main=card("Bot join approval",toggle("enabled","Require approval for new bots")+field("channel","Private approval channel","text","Timi confirmation channel.")+toggle("restrict","Restrict bot permissions until approved","Apply temporary channel restrictions while approval is pending."),"Bot access control");
side=card("Approval flow",'<p class="empty-note">New bot joins are sent to the private confirmation channel. The server owner can approve or reject the request. Do not grant untrusted bots Administrator.</p>');
}else if(page==="image-checks"){
main=card("Local image analysis",toggle("enabled","Enable image checks")+field("maxSize","Maximum image size (MB)","number")+toggle("ocr","Extract text with OCR")+toggle("qr","Decode QR codes")+toggle("duplicate","Check duplicate images")+toggle("urlChecks","Inspect URLs found in images"),"No AI API required");
side=card("Capabilities & limits",'<p class="empty-note">Local tools can inspect format, dimensions, hashes, OCR text, QR codes, duplicates and simple URL heuristics. This is not AI image understanding and does not reliably classify nudity, violence or graphic content.</p>');
}else if(page==="moderation-cases"){
main=card("Case management",toggle("enabled","Enable moderation case logging")+field("retention","Warning retention (days)","number")+field("logChannel","Moderation log channel","text"),"Warnings and sanctions")+card("Case list",'<div class="toolbar"><input class="search-input" placeholder="Search user or case ID"><button class="button secondary small" data-action="search-cases">Search</button></div><div class="empty-state"><strong>No cases loaded</strong>Live warnings and sanctions appear here after the API is connected.</div>');
side=card("Case actions",'<p class="empty-note">Review warnings, timeouts, kicks, bans and deleted messages. The Discord bot remains the source of truth for moderation actions.</p>');
}else if(page==="recovery"){
main=card("Recovery settings",toggle("enabled","Enable recovery snapshots")+field("storage","Storage allocation (MB)","number")+field("retention","Retention window (days)","number")+toggle("messages","Back up message content")+toggle("channels","Snapshot channel settings"),"Bounded server recovery");
side=card("Recovery limits",'<p class="empty-note">Current server storage allocation is fixed at 5 MB. Message and channel recovery is bounded and cannot restore every deleted Discord object or attachment.</p>');
}else if(page==="security-audit"){
main=card("Security audit",toggle("enabled","Enable audit logging")+field("logChannel","Security log channel","text")+'<div class="divider"></div><button class="button secondary" data-action="run-audit">Run security audit</button>',"Server configuration review")+card("Audit results",'<div class="empty-state"><strong>No audit has been run</strong>Run the audit from the connected bot to inspect server configuration.</div>');
side=card("Audit scope",'<p class="empty-note">The audit reviews common server configuration and permission risks. It is not a penetration test and cannot detect compromised accounts or every permission path.</p>');
}else if(page==="ticket-setup"){
main=card("Ticket environment",toggle("enabled","Enable ticket system")+field("category","Ticket category name","text")+field("logChannel","Ticket log channel","text")+field("supportRole","Support role ID","text"),"Server setup")+card("Setup checklist",'<div class="toggle-row"><div class="toggle-copy"><strong>Private ticket category</strong><small>Tickets are created in a restricted category.</small></div><span class="pill">Required</span></div><div class="toggle-row"><div class="toggle-copy"><strong>Support access</strong><small>Support staff can view and respond.</small></div><span class="pill">Required</span></div>');
side=card("Permissions",'<p class="empty-note">Timi needs Manage Channels and permission to create private channels and manage their overwrites.</p>');
}else if(page==="ticket-panel"){
main=card("Ticket panel content",toggle("enabled","Enable ticket panel")+field("title","Panel title")+area("description","Panel description")+field("button","Open button label")+field("channel","Panel destination channel","text"),"Customize the public entry point")+card("Panel preview",'<div class="preview-box"><strong>'+esc(cfg.title||"Contact support")+'</strong><p>'+esc(cfg.description||"Open a ticket and our team will help you.")+'</p><button class="button small secondary" type="button"> '+esc(cfg.button||"Open Ticket")+' </button></div>');
side=card("Publishing",'<p class="empty-note">The panel can be posted or refreshed in a Discord channel. Existing published panels should be updated rather than duplicated.</p>');
}else if(page==="ticket-settings"){
main=card("Ticket behavior",field("supportRole","Support role ID","text")+field("transcriptChannel","Transcript channel ID","text")+field("maxMessages","Maximum transcript messages","number")+field("closeDelay","Close confirmation delay (seconds)","number")+toggle("staffThread","Create staff discussion thread"),"Support workflow");
side=card("Ticket lifecycle",'<p class="empty-note">Tickets use private channels, staff access, close confirmation and transcript logging. The bot must retain access until the transcript has been saved.</p>');
}else if(page==="ticket-history"){
main=card("Ticket history",'<div class="toolbar"><input class="search-input" placeholder="Search ticket or member"><select class="search-input" style="max-width:140px"><option>All tickets</option><option>Open</option><option>Closed</option></select></div><div class="empty-state"><strong>No ticket history loaded</strong>Connect the API to browse open and closed tickets and transcripts.</div>');
side=card("Transcript storage",'<p class="empty-note">Transcripts are generated from ticket channel history. The dashboard should display metadata and links, not expose private transcript content to unauthorized roles.</p>');
}else if(page==="projects"){
main=card("TbScript projects",'<div class="toolbar"><input class="search-input" placeholder="Search projects"><button class="button" data-action="new-project">New project</button></div><div class="empty-state"><strong>No projects loaded</strong>Connect the API to browse projects saved for this server.</div>');
side=card("Project safety",'<p class="empty-note">TbScript is a restricted language. Projects are validated before execution and do not run arbitrary JavaScript, shell commands or filesystem operations.</p>');
}else if(page==="script-editor"){
main=card("Project details",field("name","Project name")+ '<div class="field"><label for="script-source">Source (.tdl)</label><textarea class="code-editor" id="script-source" name="source">'+esc(cfg.source||"")+'</textarea></div><div class="inline-actions"><button class="button secondary" data-action="validate-script">Validate</button><button class="button secondary" data-action="run-script">Run project</button>'+saveButton()+'</div>',"Restricted TbScript source");
side=card("Language reference",'<p class="empty-note">Use panel:, onclick id:, on member join:, on message create:, if, else and end. Four-space indentation is required. Projects are saved but not automatically run.</p><button class="button secondary small" data-action="script-help">Open language guide</button>');
}else if(page==="script-templates"){
main=card("Starter templates",'<div class="system-list">'+[["panel","Basic panel","A simple message panel with a button."],["welcome","Welcome automation","A member-join event response."],["ticket","Ticket panel","A private ticket creation flow."],["role-picker","Role picker","A role selection panel."]].map(x=>'<div class="system-row"><div class="system-copy"><strong>'+x[1]+'</strong><small>'+x[2]+'</small></div><button class="button secondary small" data-template="'+x[0]+'">Use template</button></div>').join("")+'</div>');
side=card("Component kit",'<p class="empty-note">Templates are starting points. Validate a project before running it and review each action for permission requirements.</p>');
}else if(page==="script-history"){
main=card("Version history",'<div class="empty-state"><strong>No project history loaded</strong>Up to ten previous versions can be retained per project. Connect the API to review, undo or redo changes.</div>');
side=card("Version controls",'<p class="empty-note">Restoring a version replaces the current project source. Export important versions before making major changes.</p>');
}else if(page==="script-import"){
main=card("Project transfer",'<div class="field"><label for="import-file">Import .tdl file</label><input id="import-file" type="file" accept=".tdl,text/plain"></div><button class="button secondary" data-action="import-script">Import project</button><div class="divider"></div><button class="button secondary" data-action="export-script">Export current draft</button>');
side=card("File limits",'<p class="empty-note">TbScript source files are limited to 64 KB and 2,000 lines. Imported files must be valid UTF-8 .tdl source.</p>');
}else if(page==="server-settings"){
main=card("Server preferences",selectField("language","Dashboard language",[["en-US","English (US)"],["en-GB","English (UK)"],["fil","Filipino"]])+field("timezone","Time zone")+field("prefix","Command style")+field("embedColor","Default embed color","color"),"General settings");
side=card("Storage",'<p class="empty-note">Timi uses a bounded 5 MB allocation per server for saved settings, embeds, projects and panel scripts. The dashboard does not change this allocation.</p>');
}else if(page==="permissions"){
main=card("Dashboard access",field("managerRole","Manager role ID","text","Only members with this role may manage configured systems.")+toggle("ownerOnly","Keep sensitive actions owner-only","Install/uninstall libraries and destructive actions should remain owner restricted."),"Role-based access");
side=card("Permission model",'<p class="empty-note">The API must validate Discord guild ownership or Manage Server permission on every request. Hiding controls in the browser is not an authorization check.</p>');
}
return heading(page,saveButton())+'<form id="settings-form" data-page="'+page+'"><div class="grid section-grid"><div>'+main+'</div><div>'+side+'</div></div></form>';
}
function renderListPage(page){
if(page==="saved-embeds")return heading(page,'<button class="button" data-goto="embed-editor">Create embed</button>')+card("Saved embeds",'<div class="empty-state"><strong>No saved embeds in preview</strong>Saved embeds from your server will appear here after connecting the API.</div>');
if(page==="moderation-cases"||page==="ticket-history"||page==="projects"||page==="script-history")return renderFormPage(page);
return renderFormPage(page);
}
function render(){
currentPage=location.hash.replace("#","")||"overview";
if(!pageNames[currentPage])currentPage="overview";
setActive(currentPage);
$("#page-content").innerHTML=currentPage==="overview"?renderOverview():renderListPage(currentPage);
}
function collectForm(form){const page=form.dataset.page;state[page]=state[page]||{};$$("[name]",form).forEach(input=>{state[page][input.name]=input.type==="checkbox"?input.checked:input.value;});saveState();}
document.addEventListener("click",event=>{
const expand=event.target.closest("[data-expand]");if(expand){expand.closest(".nav-group").classList.toggle("collapsed");return;}
const go=event.target.closest("[data-goto]");if(go){navigate(go.dataset.goto);return;}
const template=event.target.closest("[data-template]");if(template){const templates={panel:'panel:\n    title "Welcome"\n    description "Welcome to our server."\n    color "#808080"\n    button "Continue" : start\n\nonclick start:\n    reply "Hello."\nend',welcome:'on member join:\n    send #welcome "Welcome @author to @server!"\nend',ticket:'panel:\n    title "Support"\n    description "Open a private ticket."\n    button "Open Ticket" : ticket\n\nonclick ticket:\n    create channel "ticket"\n    make private\n    allow @author\n    reply "Your ticket is open."\nend', "role-picker":'panel:\n    title "Choose your roles"\n    description "Select your interests."\n    button "Announcements" : announcements\n\nonclick announcements:\n    give role "Announcements"\n    reply "Role updated."\nend'};state["script-editor"]=state["script-editor"]||{};state["script-editor"].source=templates[template.dataset.template];saveState();navigate("script-editor");return;}
const action=event.target.closest("[data-action]");if(!action)return;
const name=action.dataset.action;
if(name==="refresh"){render();toast("Dashboard preview refreshed.");}
else if(name==="save-embed"){saveState();toast("Embed draft saved in this browser.");}
else if(name==="post-embed"){toast("Publishing requires the Termux API connection.");}
else if(name==="run-audit"){toast("Connect the bot API to run a live security audit.");}
else if(name==="search-cases"){toast("Live case search requires the bot API.");}
else if(name==="new-project"){navigate("script-editor");toast("Create a project draft, then save it.");}
else if(name==="validate-script"){toast("Validation preview: connect the API for the bot's authoritative TbScript validator.");}
else if(name==="run-script"){toast("Running scripts requires an authenticated bot API request.");}
else if(name==="script-help"){toast("TbScript uses panel:, onclick:, on events, if, else and end.");}
else if(name==="import-script"){const file=$("#import-file")?.files?.[0];if(!file){toast("Choose a .tdl file first.");return;}if(file.size>65536){toast("The .tdl file exceeds 64 KB.");return;}const reader=new FileReader();reader.onload=()=>{state["script-editor"]=state["script-editor"]||{};state["script-editor"].source=String(reader.result||"");state["script-editor"].name=file.name.replace(/\.tdl$/i,"");saveState();toast("Imported into the local draft. Save it after reviewing.");};reader.readAsText(file);return;}
else if(name==="export-script"){const source=state["script-editor"]?.source||"";const blob=new Blob([source],{type:"text/plain;charset=utf-8"});const url=URL.createObjectURL(blob);const a=document.createElement("a");a.href=url;a.download=(state["script-editor"]?.name||"timi-project")+".tdl";a.click();URL.revokeObjectURL(url);}
else if(name==="add-role"){toast("Role options will load from Discord after API connection.");}
});
document.addEventListener("submit",event=>{if(event.target.id==="settings-form"){event.preventDefault();collectForm(event.target);toast("Saved locally in this browser. Bot sync is not connected.");}});
window.addEventListener("hashchange",render);
$("#mobile-menu").addEventListener("click",()=>$("#sidebar").classList.toggle("open"));
$("#help-button").addEventListener("click",()=>toast("Timi dashboard preview. Configure a server after the API bridge is connected."));
document.addEventListener("click",event=>{if(event.target.closest(".nav-item")&&innerWidth<=720)$("#sidebar").classList.remove("open");});
render();