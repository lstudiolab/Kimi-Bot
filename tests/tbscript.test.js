import test from "node:test";
import assert from "node:assert/strict";
import { parseTbScript, compileTbScript, autoFixTbScript } from "../src/tbscript.js";

const ticket = [
  "panel:",
  '    title "Ticket Support"',
  '    description "Click below to create a private ticket."',
  '    color "#808080"',
  '    button "Open Ticket" : ticket',
  "",
  "onclick ticket:",
  '    create channel "ticket"',
  "    make private",
  "    allow @author",
  '    reply "Your ticket has been created."',
  "end"
].join("\n");

test("TBScript parses the simple panel and ticket button syntax", () => {
  const parsed = parseTbScript(ticket);
  assert.equal(parsed.ok, true);
  const compiled = compileTbScript(ticket);
  assert.equal(compiled.ok, true, JSON.stringify(compiled.errors));
  assert.equal(compiled.output.title, "Ticket Support");
  assert.equal(compiled.output.color, 0x808080);
  assert.equal(compiled.output.buttons[0].id, "ticket");
  assert.deepEqual(compiled.output.buttons[0].action.map(action => action.type),
    ["create_channel", "make_private", "allow", "reply"]);
});

test("TBScript supports role buttons and text replies", () => {
  const source = [
    "panel:",
    '    title "Verification"',
    '    button "Verify" : verify',
    "",
    "onclick verify:",
    '    give role "Verified"',
    '    reply "Verified!"',
    "end"
  ].join("\n");
  const compiled = compileTbScript(source);
  assert.equal(compiled.ok, true, JSON.stringify(compiled.errors));
  assert.deepEqual(compiled.output.buttons[0].action.map(action => action.type), ["give_role", "reply"]);
});

test("TBScript supports member-join and message-create events", () => {
  const source = [
    "on member join:",
    '    send #welcome "Welcome @author!"',
    "end",
    "",
    "on message create:",
    '    if message.content == "hello":',
    '        reply "Hello!"',
    "    else:",
    '        reply "Welcome."',
    "    end",
    "end"
  ].join("\n");
  const compiled = compileTbScript(source);
  assert.equal(compiled.ok, true, JSON.stringify(compiled.errors));
  assert.deepEqual(compiled.output.handlers.events.map(event => event.event), ["member join", "message create"]);
  const conditional = compiled.output.handlers.events[1].actions[0];
  assert.equal(conditional.type, "if");
  assert.equal(conditional.then[0].args[0], "Hello!");
  assert.equal(conditional.else[0].args[0], "Welcome.");
});

test("TBScript rejects unknown keywords and malformed blocks", () => {
  for (const source of [
    "panel:\n    unknown value",
    "onclick missing:\n    reply \"hello\"",
    "on message create:\n    reply \"hello\"",
    "panel:\n title \"bad indent\""
  ]) {
    assert.equal(compileTbScript(source).ok, false, source);
  }
});

test("TBScript rejects duplicate button IDs and missing handlers", () => {
  const duplicate = [
    "panel:",
    '    button "One" : same',
    '    button "Two" : same',
    "",
    "onclick same:",
    '    reply "ok"',
    "end"
  ].join("\n");
  assert.equal(compileTbScript(duplicate).ok, false);
  const missing = ["panel:", '    button "No handler" : missing'].join("\n");
  assert.equal(compileTbScript(missing).ok, false);
});

test("TBScript accepts comments, smart quotes and normalized line endings", () => {
  const source = [
    "-- ticket panel",
    "panel:",
    "    title “Tickets”",
    "    color “#808080”"
  ].join("\r\n");
  const compiled = compileTbScript(source);
  assert.equal(compiled.ok, true, JSON.stringify(compiled.errors));
  assert.equal(compiled.output.title, "Tickets");
  assert.equal(autoFixTbScript(source).includes("\r"), false);
});

test("TBScript preserves legacy brace projects during the syntax upgrade", () => {
  const source = '{\n  {title:"Legacy"}\n  {description:"Still supported"}\n}';
  const compiled = compileTbScript(source);
  assert.equal(compiled.ok, true);
  assert.equal(compiled.output.title, "Legacy");
});


test("TBScript rejects duplicate event handlers and excessive nesting", () => {
  const duplicate = [
    "on member join:",
    '    reply "one"',
    "end",
    "on member join:",
    '    reply "two"',
    "end"
  ].join("\n");
  assert.equal(compileTbScript(duplicate).ok, false);
  const nested = ["on message create:", ...Array.from({length: 32}, () => "    if true:")].join("\n");
  assert.equal(compileTbScript(nested).ok, false);
});

test("TBScript validates Discord's aggregate embed text limit", () => {
  const source = [
    "panel:",
    '    description "' + "D".repeat(4096) + '"',
    '    footer "' + "F".repeat(2048) + '"'
  ].join("\n");
  assert.equal(compileTbScript(source).ok, false);
});


test("TBScript rejects onclick handlers that reference missing buttons", () => {
  const source = [
    "panel:",
    '    button "Existing" : existing',
    "",
    "onclick missing:",
    '    reply "This must not silently do nothing."',
    "end",
    "",
    "onclick existing:",
    '    reply "Works."',
    "end"
  ].join("\n");
  assert.equal(compileTbScript(source).ok, false);
});


test("TBScript compiles every published panel property and action keyword", () => {
  const source = [
    "panel:",
    '    title "Complete panel"',
    '    description "Description"',
    '    footer "Footer"',
    '    author "Timi"',
    '    color "#808080"',
    '    image "https://example.com/image.png"',
    '    thumbnail "https://example.com/thumb.png"',
    '    url "https://example.com"',
    '    content "Panel content"',
    '    field "Status" "Ready"',
    "    ephemeral true",
    '    button "Run" : run',
    "",
    "onclick run:",
    '    send #logs "Action started by @authorID"',
    '    create channel "private-room"',
    "    make private",
    "    allow @author",
    '    give role "Member"',
    '    remove role "Visitor"',
    '    reply "Complete"',
    "end"
  ].join("\n");
  const compiled = compileTbScript(source);
  assert.equal(compiled.ok, true, JSON.stringify(compiled.errors));
  assert.equal(compiled.output.ephemeral, true);
  assert.equal(compiled.output.fields.length, 1);
  assert.deepEqual(compiled.output.buttons[0].action.map(action => action.type), [
    "send", "create_channel", "make_private", "allow", "give_role", "remove_role", "reply"
  ]);
});
