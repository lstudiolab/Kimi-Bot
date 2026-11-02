import test from "node:test";
import assert from "node:assert/strict";
import { conditionMatches } from "../src/automations/engine.js";

test("automation conditions match account age thresholds",()=>{
  assert.equal(conditionMatches({type:"account_age_under_days",value:7},{accountAgeDays:2}),true);
  assert.equal(conditionMatches({type:"account_age_under_days",value:7},{accountAgeDays:20}),false);
});

test("invite condition recognizes Discord invite formats",()=>{
  assert.equal(conditionMatches({type:"contains_invite"},{message:{content:"Join https://discord.gg/example"}}),true);
  assert.equal(conditionMatches({type:"contains_invite"},{message:{content:"https://discord.com/invite/example"}}),true);
  assert.equal(conditionMatches({type:"contains_invite"},{message:{content:"ordinary message"}}),false);
});

test("unconditional automation steps always continue",()=>{
  assert.equal(conditionMatches({type:"always"},{}),true);
  assert.equal(conditionMatches(null,{}),true);
});
