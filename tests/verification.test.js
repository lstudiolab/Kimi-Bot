import test from "node:test";
import assert from "node:assert/strict";
import { Verification } from "../src/systems/verification.js";

test("verification runs on join and no longer exposes risk scoring or manual verify", () => {
  assert.equal(typeof Verification.prototype.memberJoin, "function");
  assert.equal(typeof Verification.prototype.score, "undefined");
  assert.equal(typeof Verification.prototype.verify, "undefined");
});

test("verification audit entries persist per guild and are capped", () => {
  const store = { data: {}, save() {} };
  const logger = { info() {} };
  const verification = new Verification({}, store, logger);
  const guild = { id: "guild-1", name: "Example Server" };
  const member = {
    id: "123456789012345678",
    user: { username: "member-one" },
    displayName: "Member One"
  };

  for (let index = 0; index < 305; index++) {
    verification.recordAudit(guild, member, "passed", [
      { name: "Account age", status: "pass", detail: "Account meets minimum age." }
    ], "Verified automatically.");
  }

  assert.equal(store.data.verification_logs["guild-1"].length, 300);
  assert.equal(store.data.verification_logs["guild-1"][0].username, "member-one");
  assert.equal(store.data.verification_logs["guild-1"][0].checks[0].status, "pass");
  assert.equal(store.data.verification_logs["other-guild"], undefined);
});
