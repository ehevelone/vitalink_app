const assert = require("node:assert/strict");
const test = require("node:test");

const db = require("../services/db");
const userAuth = require("../services/user-auth");

test("a transfer code stays bound to its first destination device", async () => {
  const originalQuery = db.query;
  const originalVerify = userAuth.verifyUserSession;
  let redeemedDeviceId = null;

  userAuth.verifyUserSession = async () => true;
  db.query = async (sql, params = []) => {
    if (sql.includes("FROM user_devices")) {
      return { rows: [{ active: true }], rowCount: 1 };
    }
    if (sql.includes("UPDATE device_transfer_packages")) {
      const deviceId = params[2];
      if (redeemedDeviceId && redeemedDeviceId !== deviceId) {
        return { rows: [], rowCount: 0 };
      }
      redeemedDeviceId = deviceId;
      return {
        rows: [{ id: "transfer-1", chunk_count: 2, expires_at: new Date() }],
        rowCount: 1,
      };
    }
    return { rows: [], rowCount: 0 };
  };

  delete require.cache[require.resolve("../redeem_device_transfer")];
  const { handler } = require("../redeem_device_transfer");
  const event = (deviceId) => ({
    httpMethod: "POST",
    body: JSON.stringify({
      userId: "42",
      sessionToken: "session",
      deviceId,
      transferCode: "VT-TEST",
    }),
  });

  try {
    const first = await handler(event("new-phone"));
    assert.equal(first.statusCode, 200);

    const retry = await handler(event("new-phone"));
    assert.equal(retry.statusCode, 200);

    const otherDevice = await handler(event("different-phone"));
    assert.equal(otherDevice.statusCode, 404);
  } finally {
    db.query = originalQuery;
    userAuth.verifyUserSession = originalVerify;
    delete require.cache[require.resolve("../redeem_device_transfer")];
  }
});
