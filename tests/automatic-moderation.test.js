import test from "node:test";
import assert from "node:assert/strict";
import { automaticEscalation } from "../src/systems/moderation.js";

test("first AutoMod strike uses the configured baseline action",()=>{
  assert.deepEqual(automaticEscalation(1,"timeout",10),{action:"timeout",timeoutMinutes:10,level:"initial"});
  assert.deepEqual(automaticEscalation(1,"delete",10),{action:"delete",timeoutMinutes:10,level:"initial"});
});

test("second AutoMod strike escalates to a timeout",()=>{
  assert.deepEqual(automaticEscalation(2,"delete",10),{action:"timeout",timeoutMinutes:10,level:"repeat"});
});

test("third AutoMod strike escalates to a one-hour timeout",()=>{
  assert.deepEqual(automaticEscalation(3,"timeout",5),{action:"timeout",timeoutMinutes:60,level:"continued"});
});

test("fourth and later AutoMod strikes escalate to a kick, never an automatic ban",()=>{
  assert.deepEqual(automaticEscalation(4,"ban",10),{action:"kick",timeoutMinutes:60,level:"persistent"});
  assert.equal(automaticEscalation(50,"timeout",10).action,"kick");
});

test("automatic escalation clamps invalid baseline timeout values",()=>{
  assert.equal(automaticEscalation(1,"timeout",999999).timeoutMinutes,40320);
  assert.equal(automaticEscalation(2,"timeout",-1).timeoutMinutes,5);
});
