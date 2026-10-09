const assert = require("node:assert/strict");
const test = require("node:test");

const {
  sendRevocationPushWithTimeout,
} = require("../services/device-security");

test("revocation push cannot block device-switch login indefinitely", async () => {
  const messaging = {
    sendEachForMulticast: () => new Promise(() => {}),
  };

  const startedAt = Date.now();
  await assert.rejects(
    sendRevocationPushWithTimeout(messaging, { tokens: ["test"] }, 20),
    /Revocation push timed out/
  );
  assert.ok(Date.now() - startedAt < 500);
});

test("successful revocation push result is preserved", async () => {
  const expected = { successCount: 1, failureCount: 0 };
  const messaging = {
    sendEachForMulticast: async () => expected,
  };

  const actual = await sendRevocationPushWithTimeout(
    messaging,
    { tokens: ["test"] },
    100
  );
  assert.deepEqual(actual, expected);
});
