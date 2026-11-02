import { SlashCommandBuilder, PermissionFlagsBits, ChannelType } from "discord.js";

const allCommandBuilders=[
  new SlashCommandBuilder().setName("kimi").setDescription("Open Kimi server configuration dashboard.").setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild),
  new SlashCommandBuilder().setName("configure-foundation").setDescription("Configure the Foundation plugin.").setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild),
  new SlashCommandBuilder().setName("configure-kimi-lock").setDescription("Configure the Kimi Lock plugin.").setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild),
  new SlashCommandBuilder().setName("configure-support").setDescription("Configure Kimi Support plugin.").setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild),
  new SlashCommandBuilder().setName("plan").setDescription("View Kimi's free features and storage usage."),
  new SlashCommandBuilder().setName("web-token").setDescription("Link this server to your Kimi dashboard using a one-time token.").setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild),
  new SlashCommandBuilder().setName("install").setDescription("Install a Kimi plugin.").addStringOption(o=>o.setName("plugin").setDescription("Plugin to install").setRequired(true).addChoices({name:"Foundation",value:"Foundation"},{name:"Kimi Lock",value:"Kimi Lock"},{name:"Support",value:"Support"},)),
  new SlashCommandBuilder().setName("plugins").setDescription("Show available plugins."),
  new SlashCommandBuilder().setName("automations").setDescription("Build and manage server automations."),
  new SlashCommandBuilder().setName("uninstall").setDescription("Disable a Kimi plugin (server owner only).").addStringOption(o=>o.setName("plugin").setDescription("Plugin to uninstall").setRequired(true).addChoices({name:"Foundation",value:"Foundation"},{name:"Kimi Lock",value:"Kimi Lock"},{name:"Support",value:"Support"},)),

  new SlashCommandBuilder().setName("setup").setDescription("Set up Kimi channels and server systems."),
  new SlashCommandBuilder().setName("welcome").setDescription("Configure welcome and goodbye messages.")
    .addChannelOption(o=>o.setName("welcome-channel").setDescription("Channel for new member greetings").addChannelTypes(ChannelType.GuildText))
    .addChannelOption(o=>o.setName("goodbye-channel").setDescription("Channel for member departure messages").addChannelTypes(ChannelType.GuildText))
    .addStringOption(o=>o.setName("welcome-message").setDescription("Welcome message template").setMaxLength(1800))
    .addStringOption(o=>o.setName("goodbye-message").setDescription("Goodbye message template").setMaxLength(1800)),
  new SlashCommandBuilder().setName("autorole").setDescription("Set or disable the automatic member role.")
    .addRoleOption(o=>o.setName("role").setDescription("Role to assign to new members")),
  new SlashCommandBuilder().setName("moderation").setDescription("Create or update the moderation settings panel."),
  new SlashCommandBuilder().setName("tickets").setDescription("Prepare the ticket category and private support channels."),
  new SlashCommandBuilder().setName("ticket-panel").setDescription("Create or update the ticket panel."),
  new SlashCommandBuilder().setName("ticket-config").setDescription("View ticket settings and configure support roles."),

  new SlashCommandBuilder().setName("roles").setDescription("Create a self-service role selection menu."),
  new SlashCommandBuilder().setName("embed-new").setDescription("Create a reusable server embed."),
  new SlashCommandBuilder().setName("embed-post").setDescription("Place a saved embed in this channel.").addStringOption(o=>o.setName("name").setDescription("Saved embed name").setRequired(true).setMaxLength(24)),
  new SlashCommandBuilder().setName("embed-edit").setDescription("Edit a saved embed.").addStringOption(o=>o.setName("name").setDescription("Saved embed name").setRequired(true).setMaxLength(24)),

  new SlashCommandBuilder().setName("verify").setDescription("Configure button-based member verification."),
  new SlashCommandBuilder().setName("verify-config").setDescription("Configure button-based member verification (legacy alias).")
    .addRoleOption(o=>o.setName("role").setDescription("Role assigned after a successful check"))
    .addChannelOption(o=>o.setName("channel").setDescription("Public channel where new members see the Verify button").addChannelTypes(ChannelType.GuildText))
    .addIntegerOption(o=>o.setName("min-age-days").setDescription("Minimum Discord account age in days").setMinValue(0).setMaxValue(3650))
    .addChannelOption(o=>o.setName("review-channel").setDescription("Private channel for manual reviews").addChannelTypes(ChannelType.GuildText)),
  new SlashCommandBuilder().setName("filter").setDescription("Manage blocked words and phrases.")
    .addSubcommand(s=>s.setName("add").setDescription("Block a word or phrase").addStringOption(o=>o.setName("phrase").setDescription("Phrase to block").setRequired(true).setMaxLength(100)))
    .addSubcommand(s=>s.setName("remove").setDescription("Unblock a word or phrase").addStringOption(o=>o.setName("phrase").setDescription("Phrase to remove").setRequired(true).setMaxLength(100)))
    .addSubcommand(s=>s.setName("list").setDescription("List blocked words and phrases")),
  new SlashCommandBuilder().setName("security").setDescription("Audit this server for common security risks."),
 ];

const commandGroups=Object.freeze({
  Core:["kimi","configure-foundation","configure-kimi-lock","configure-support","plan","web-token","plugins","automations"],
  Foundation:["setup","welcome","autorole","roles","embed-new","embed-edit","embed-post"],
  "Kimi Lock":["verify","verify-config","filter","security","moderation"],
  Support:["tickets","ticket-panel","ticket-config"],
});
const adminOnlyCommands=new Set(Object.entries(commandGroups).filter(([name])=>name!=="Core").flatMap(([,names])=>names));
for(const command of allCommandBuilders)if(adminOnlyCommands.has(command.name))command.setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild);
const commandByName=new Map(allCommandBuilders.map(command=>[command.name,command]));
export const commandData=allCommandBuilders.map(command=>command.toJSON());
export const coreCommandData=commandGroups.Core.map(name=>commandByName.get(name).toJSON());
export function commandsForPlugins(installedPlugins=[]){
  const names=new Set(commandGroups.Core);
  for(const plugin of installedPlugins)for(const name of commandGroups[plugin]||[])names.add(name);
  return [...names].map(name=>commandByName.get(name)?.toJSON()).filter(Boolean);
}
export function pluginCommandsForPlugins(installedPlugins=[]){
  const names=new Set();
  for(const plugin of installedPlugins)for(const name of commandGroups[plugin]||[])names.add(name);
  return [...names].map(name=>commandByName.get(name)?.toJSON()).filter(Boolean);
}

export function pluginForCommand(name){
  for(const [plugin,names] of Object.entries(commandGroups))if(plugin!=="Core"&&names.includes(name))return plugin;
  return null;
}

export const commandsForLibraries=commandsForPlugins;
export const libraryCommandsForLibraries=pluginCommandsForPlugins;
export const libraryForCommand=pluginForCommand;
