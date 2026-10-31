import { SlashCommandBuilder, PermissionFlagsBits, ChannelType } from "discord.js";

const allCommandBuilders=[
  new SlashCommandBuilder().setName("timi-plan").setDescription("View Timi's free features and storage usage."),
  new SlashCommandBuilder().setName("install-library").setDescription("Install a Timi library.").addStringOption(o=>o.setName("libraryname").setDescription("Foundation, Security, Support or Scratch").setRequired(false).setMaxLength(50)),
  new SlashCommandBuilder().setName("library-list").setDescription("Show Timi's four libraries."),
  new SlashCommandBuilder().setName("uninstall-library").setDescription("Disable a Timi library (server owner only).").addStringOption(o=>o.setName("libraryname").setDescription("Library name").setRequired(true).setMaxLength(50)),

  new SlashCommandBuilder().setName("ticket-setup").setDescription("Create Timi private channels and the ticket category."),
  new SlashCommandBuilder().setName("ticket-panel").setDescription("Create or update the ticket panel."),
  new SlashCommandBuilder().setName("ticket-settings").setDescription("Edit ticket system settings."),

  new SlashCommandBuilder().setName("greet-settings").setDescription("Configure welcome and goodbye messages.")
    .addChannelOption(o=>o.setName("welcome-channel").setDescription("Welcome channel").addChannelTypes(ChannelType.GuildText))
    .addStringOption(o=>o.setName("welcome-message").setDescription("Welcome text; supports {user}, {username}, {server}, {member_count}").setMaxLength(1800))
    .addChannelOption(o=>o.setName("goodbye-channel").setDescription("Goodbye channel").addChannelTypes(ChannelType.GuildText))
    .addStringOption(o=>o.setName("goodbye-message").setDescription("Goodbye text; supports {user}, {username}, {server}, {member_count}").setMaxLength(1800)),
  new SlashCommandBuilder().setName("auto-role").setDescription("Set the role automatically assigned to new members.").addRoleOption(o=>o.setName("role").setDescription("Role to assign; omit to disable")),
  new SlashCommandBuilder().setName("setup-role-picker").setDescription("Create a self-service role selection menu."),
  new SlashCommandBuilder().setName("create-embed").setDescription("Create a reusable server embed."),
  new SlashCommandBuilder().setName("place-embed").setDescription("Place a saved embed in this channel.").addStringOption(o=>o.setName("name").setDescription("Saved embed name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("edit-embed").setDescription("Edit a saved embed.").addStringOption(o=>o.setName("name").setDescription("Saved embed name").setRequired(true).setMaxLength(24)),

  new SlashCommandBuilder().setName("verify-settings").setDescription("Configure risk-based member verification.")
    .addRoleOption(o=>o.setName("role").setDescription("Role granted after passing"))
    .addRoleOption(o=>o.setName("required-role").setDescription("Role required before verifying"))
    .addBooleanOption(o=>o.setName("clear-required-role").setDescription("Remove the required-role restriction"))
    .addIntegerOption(o=>o.setName("min-age-days").setDescription("Minimum account age in days").setMinValue(0).setMaxValue(3650))
    .addChannelOption(o=>o.setName("review-channel").setDescription("Manual review channel").addChannelTypes(ChannelType.GuildText))
    .addStringOption(o=>o.setName("title").setDescription("Verification panel title").setMaxLength(200))
    .addStringOption(o=>o.setName("description").setDescription("Verification panel description").setMaxLength(1000)),
  new SlashCommandBuilder().setName("verify-panel").setDescription("Publish the verification panel."),
  new SlashCommandBuilder().setName("moderation-settings").setDescription("Configure moderation and anti-spam protection."),
  new SlashCommandBuilder().setName("automod-word").setDescription("Manage blocked words and phrases.")
    .addSubcommand(s=>s.setName("add").setDescription("Block a word or phrase.").addStringOption(o=>o.setName("phrase").setDescription("Word or phrase").setRequired(true).setMaxLength(100)))
    .addSubcommand(s=>s.setName("remove").setDescription("Remove a blocked word or phrase.").addStringOption(o=>o.setName("phrase").setDescription("Exact phrase").setRequired(true).setMaxLength(100)))
    .addSubcommand(s=>s.setName("list").setDescription("List blocked words and phrases.")),

  new SlashCommandBuilder().setName("code").setDescription("Create a TbScript project.")
    .addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24))
    .addAttachmentOption(o=>o.setName("file").setDescription("Optional .tdl source file (up to 64 KB)")),
  new SlashCommandBuilder().setName("code-edit").setDescription("Edit a TbScript project or supported Timi panel.")
    .addStringOption(o=>o.setName("target").setDescription("What to edit").setRequired(true)
      .addChoices({name:"Project",value:"project"},{name:"Ticket panel",value:"ticket-panel"},{name:"Verification panel",value:"verification-panel"},{name:"Moderation panel",value:"moderation-panel"},{name:"Role picker panels",value:"role-picker-panel"}))
    .addStringOption(o=>o.setName("name").setDescription("Project name").setMaxLength(24))
    .addAttachmentOption(o=>o.setName("file").setDescription("Optional .tdl source file")),
  new SlashCommandBuilder().setName("code-list").setDescription("List saved TbScript projects."),
  new SlashCommandBuilder().setName("code-run").setDescription("Test a saved TbScript project.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("code-stop").setDescription("Stop a running TbScript project.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("code-delete").setDescription("Delete a TbScript project.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("code-export").setDescription("Export a TbScript project as a .tdl file.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("code-import").setDescription("Import a TbScript .tdl file.").addAttachmentOption(o=>o.setName("file").setDescription("TbScript .tdl file").setRequired(true)).addBooleanOption(o=>o.setName("replace").setDescription("Replace an existing project and keep its history")),
  new SlashCommandBuilder().setName("code-history").setDescription("Show saved project versions.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("code-validate").setDescription("Validate a TbScript project.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("code-undo").setDescription("Undo the last project change.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("code-redo").setDescription("Redo the last undone project change.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("code-kit").setDescription("Open the TbScript component kit."),
  new SlashCommandBuilder().setName("code-docs").setDescription("Open TbScript documentation.").addStringOption(o=>o.setName("topic").setDescription("Documentation topic")
    .addChoices({name:"Syntax",value:"syntax"},{name:"Keywords",value:"keywords"},{name:"Actions",value:"actions"},{name:"Placeholders",value:"placeholders"},{name:"Safety",value:"safety"})),
  new SlashCommandBuilder().setName("code-template").setDescription("Create a TbScript starter project.")
    .addStringOption(o=>o.setName("name").setDescription("New project name").setRequired(true).setMaxLength(24))
    .addStringOption(o=>o.setName("template").setDescription("Starter template").setRequired(true)
      .addChoices({name:"Embed",value:"embed"},{name:"Button",value:"button"},{name:"Modal",value:"modal"},{name:"Welcome panel",value:"welcome"},{name:"Ticket panel",value:"ticket"},{name:"Verification panel",value:"verification"}))
];

const commandGroups=Object.freeze({
  Core:["timi-plan","install-library","library-list","uninstall-library"],
  Foundation:["greet-settings","auto-role","setup-role-picker","create-embed","edit-embed","place-embed"],
  Security:["verify-settings","verify-panel","moderation-settings","automod-word"],
  Support:["ticket-setup","ticket-panel","ticket-settings"],
  Scratch:["code","code-edit","code-list","code-run","code-stop","code-delete","code-export","code-import","code-history","code-validate","code-undo","code-redo","code-kit","code-docs","code-template"]
});
const adminOnlyCommands=new Set(Object.entries(commandGroups).filter(([name])=>name!=="Core").flatMap(([,names])=>names));
for(const command of allCommandBuilders)if(adminOnlyCommands.has(command.name))command.setDefaultMemberPermissions(PermissionFlagsBits.Administrator);
const commandByName=new Map(allCommandBuilders.map(command=>[command.name,command]));
export const commandData=allCommandBuilders.map(command=>command.toJSON());
export const coreCommandData=commandGroups.Core.map(name=>commandByName.get(name).toJSON());
export function commandsForLibraries(installedLibraries=[]){
  const names=new Set(commandGroups.Core);
  for(const library of installedLibraries)for(const name of commandGroups[library]||[])names.add(name);
  return [...names].map(name=>commandByName.get(name)?.toJSON()).filter(Boolean);
}
export function libraryCommandsForLibraries(installedLibraries=[]){
  const names=new Set();
  for(const library of installedLibraries)for(const name of commandGroups[library]||[])names.add(name);
  return [...names].map(name=>commandByName.get(name)?.toJSON()).filter(Boolean);
}
