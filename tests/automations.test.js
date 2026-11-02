import test from "node:test";
import assert from "node:assert/strict";
import { AutomationEngine, conditionMatches } from "../src/automations/engine.js";

test("automation conditions handle account age and message content",()=>{
  const context={accountAgeDays:3,message:{content:"Please join https://discord.gg/example"}};
  assert.equal(conditionMatches({type:"always"},context),true);
  assert.equal(conditionMatches({type:"account_age_under_days",value:7},context),true);
  assert.equal(conditionMatches({type:"account_age_under_days",value:2},context),false);
  assert.equal(conditionMatches({type:"contains_invite"},context),true);
  assert.equal(conditionMatches({type:"contains_link"},context),true);
  assert.equal(conditionMatches({type:"message_contains",value:"JOIN"},context),true);
  assert.equal(conditionMatches({type:"message_contains",value:"not present"},context),false);
});
test("automation channel conditions fail closed when the channel does not match",()=>{
  assert.equal(conditionMatches({type:"channel_is",value:"channel-a"},{message:{channelId:"channel-b"}}),false);
  assert.equal(conditionMatches({type:"unknown"},{message:{content:"anything"}}),false);
});

test("automation queue rejection releases the event deduplication lock",async()=>{
 const store={data:{automations:{g:[{id:"automation-1",enabled:true,trigger:"manual",condition:{type:"always"},actions:[{type:"delete_message"}]}]}}};
 const engine=new AutomationEngine({client:{},store,logger:{warn(){}},services:{background:{enqueue:()=>Promise.reject(new Error("queue full"))}}});
 await engine.run({id:"g"},"manual",{},"event-1");
 assert.equal(engine.running.size,0);
});
