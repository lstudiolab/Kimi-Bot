import test from "node:test";
import assert from "node:assert/strict";
import {GuardRateLimiter,TOKEN_CAPACITY} from "../src/systems/guard.js";
function setup(){return new GuardRateLimiter({data:{guard_state:{}},queueSave(){}});}
test("user buckets start at ten and refill one token every two seconds",()=>{
 const g=setup();for(let n=0;n<TOKEN_CAPACITY;n++)assert.equal(g.consume("g","u","user",1000+n).allowed,true);
 assert.equal(g.consume("g","u","user",1011).allowed,false);
 assert.equal(g.consume("g","u","user",3000).allowed,false,"a partial refill must not unlock the member");
 assert.equal(g.consume("g","u","user",20999).allowed,false);
 assert.equal(g.consume("g","u","user",21000).allowed,true,"the member unlocks only after all ten tokens return");
});
test("bot buckets only regenerate after two seconds without activity",()=>{
 const g=setup();for(let n=0;n<TOKEN_CAPACITY;n++)assert.equal(g.consume("g","b","bot",1000+n*100).allowed,true);
 assert.equal(g.consume("g","b","bot",2000).allowed,false);
 assert.equal(g.consume("g","b","bot",3500).allowed,false);
 assert.equal(g.consume("g","b","bot",5500).allowed,true);
});
test("user and bot buckets are independent",()=>{
 const g=setup();for(let n=0;n<TOKEN_CAPACITY;n++)g.consume("g","same","user",1000+n);
 assert.equal(g.consume("g","same","bot",2000).allowed,true);
});

import {coreCommandData} from "../src/commands.js";
test("bot restriction review is an owner-only core command",()=>{
 const command=coreCommandData.find(item=>item.name==="guard-review");
 assert.ok(command);
 assert.equal(command.options[0].name,"bot");
 assert.equal(command.options[1].name,"decision");
});

test("malformed persisted rate state is repaired instead of crashing",()=>{
 const store={data:{guard_state:{g:{users:{broken:null,old:{tokens:999,updated_at:1000}},bots:[]}}},queueSave(){}};
 const g=new GuardRateLimiter(store);
 const result=g.consume("g","u","user",2000);
 assert.equal(result.allowed,true);
 assert.equal(result.tokens,9);
 assert.equal(store.data.guard_state.g.users.old.tokens,10);
});
