import { SlashCommandBuilder, PermissionFlagsBits, ChannelType } from "discord.js";

const allCommandBuilders=[
  new SlashCommandBuilder().setName("timi-settings").setDescription("Open Timi built-in server settings panel."),
  new SlashCommandBuilder().setName("plan").setDescription("View Timi's free features and storage usage."),
  new SlashCommandBuilder().setName("install").setDescription("Install a Timi library.").addStringOption(o=>o.setName("library").setDescription("Library to install").setRequired(true).addChoices({name:"Foundation",value:"Foundation"},{name:"Security",value:"Security"},{name:"Support",value:"Support"},{name:"Scratch",value:"Scratch"})),
  new SlashCommandBuilder().setName("libraries").setDescription("Show Timi's four libraries."),
  new SlashCommandBuilder().setName("uninstall").setDescription("Disable a Timi library (server owner only).").addStringOption(o=>o.setName("library").setDescription("Library to uninstall").setRequired(true).addChoices({name:"Foundation",value:"Foundation"},{name:"Security",value:"Security"},{name:"Support",value:"Support"},{name:"Scratch",value:"Scratch"})),

  new SlashCommandBuilder().setName("tickets").setDescription("Create Timi private channels and the ticket category."),
  new SlashCommandBuilder().setName("ticket-panel").setDescription("Create or update the ticket panel."),

  new SlashCommandBuilder().setName("setup").setDescription("Create Timi log, confirmation and settings channels."),
  new SlashCommandBuilder().setName("roles").setDescription("Create a self-service role selection menu."),
  new SlashCommandBuilder().setName("embed-new").setDescription("Create a reusable server embed."),
  new SlashCommandBuilder().setName("embed-post").setDescription("Place a saved embed in this channel.").addStringOption(o=>o.setName("name").setDescription("Saved embed name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("embed-edit").setDescription("Edit a saved embed.").addStringOption(o=>o.setName("name").setDescription("Saved embed name").setRequired(true).setMaxLength(24)),

  new SlashCommandBuilder().setName("verify").setDescription("Publish the verification panel."),
  new SlashCommandBuilder().setName("security").setDescription("Audit this server for common security risks."),
  new SlashCommandBuilder().setName("script").setDescription("Create a TbScript project.")
    .addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24))
    .addAttachmentOption(o=>o.setName("file").setDescription("Optional .tdl source file (up to 64 KB)")),
  new SlashCommandBuilder().setName("script-edit").setDescription("Edit a TbScript project or supported Timi panel.")
    .addStringOption(o=>o.setName("target").setDescription("What to edit").setRequired(true)
      .addChoices({name:"Project",value:"project"},{name:"Ticket panel",value:"ticket-panel"},{name:"Verification panel",value:"verification-panel"},{name:"Moderation panel",value:"moderation-panel"},{name:"Role picker panels",value:"role-picker-panel"}))
    .addStringOption(o=>o.setName("name").setDescription("Project name").setMaxLength(24))
    .addAttachmentOption(o=>o.setName("file").setDescription("Optional .tdl source file")),
  new SlashCommandBuilder().setName("scripts").setDescription("List saved TbScript projects."),
  new SlashCommandBuilder().setName("script-run").setDescription("Test a saved TbScript project.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("script-stop").setDescription("Stop a running TbScript project.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("script-delete").setDescription("Delete a TbScript project.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("script-export").setDescription("Export a TbScript project as a .tdl file.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("script-import").setDescription("Import a TbScript .tdl file.").addAttachmentOption(o=>o.setName("file").setDescription("TbScript .tdl file").setRequired(true)).addBooleanOption(o=>o.setName("replace").setDescription("Replace an existing project and keep its history")),
  new SlashCommandBuilder().setName("script-history").setDescription("Show saved project versions.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("script-check").setDescription("Validate a TbScript project.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("script-undo").setDescription("Undo the last project change.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("script-redo").setDescription("Redo the last undone project change.").addStringOption(o=>o.setName("name").setDescription("Project name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("script-kit").setDescription("Open the TbScript component kit."),
  new SlashCommandBuilder().setName("script-help").setDescription("Open TbScript documentation.").addStringOption(o=>o.setName("topic").setDescription("Documentation topic")
    .addChoices({name:"Syntax",value:"syntax"},{name:"Keywords",value:"keywords"},{name:"Actions",value:"actions"},{name:"Placeholders",value:"placeholders"},{name:"Safety",value:"safety"})),
  new SlashCommandBuilder().setName("script-template").setDescription("Create a TbScript starter project.")
    .addStringOption(o=>o.setName("name").setDescription("New project name").setRequired(true).setMaxLength(24))
    .addStringOption(o=>o.setName("template").setDescription("Starter template").setRequired(true)
      .addChoices({name:"Embed",value:"embed"},{name:"Button",value:"button"},{name:"Modal",value:"modal"},{name:"Welcome panel",value:"welcome"},{name:"Ticket panel",value:"ticket"},{name:"Verification panel",value:"verification"}))
];

const commandGroups=Object.freeze({
  Core:["timi-settings","plan"],
  Foundation:["setup","roles","embed-new","embed-edit","embed-post"],
  Security:["verify","security"],
  Support:["tickets","ticket-panel"],
  Scratch:["script","script-edit","scripts","script-run","script-stop","script-delete","script-export","script-import","script-history","script-check","script-undo","script-redo","script-kit","script-help","script-template"]
});
const adminOnlyCommands=new Set(Object.entries(commandGroups).filter(([name])=>name!=="Core").flatMap(([,names])=>names));
for(const command of allCommandBuilders)if(adminOnlyCommands.has(command.name))command.setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild);
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

export function libraryForCommand(name){
  for(const [library,names] of Object.entries(commandGroups))if(library!=="Core"&&names.includes(name))return library;
  return null;
}
