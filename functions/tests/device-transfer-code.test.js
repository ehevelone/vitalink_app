const assert = require("node:assert/strict");
const test = require("node:test");

const db = require("../services/db");
const { hashPassword } = require("../services/passwords");
const {
  generateShortCode,
  normalizeCode,
} = require("../services/device-transfer");

test("short transfer codes use the unambiguous alphabet", () => {
  for (let i = 0; i < 50; i += 1) {
    assert.match(generateShortCode(), /^[0-9A-HJKMNP-TV-Z]{8}$/);
  }
});

test("server lookup codes forgive dashes, case and look-alike letters", () => {
  assert.equal(normalizeCode("k7qm-4tzp"), "K7QM4TZP");
  assert.equal(normalizeCode("K7QO-4TZL"), "K7Q0" + "4TZ1");
  assert.equal(normalizeCode("VT-ABCDEF0123"), "VT-ABCDEF0123", "legacy codes are untouched");
});

// check_user: a wrong transfer code must not disable the old phone.
async function loginWithTransferCode({ transferCode, packageFound }) {
  const passwordHash = await hashPassword("Password1!");
  const calls = [];
  const originalQuery = db.query;
  db.query = async (sql, params = []) => {
    const text = String(sql);
    calls.push({ sql: text, params });
    if (text.includes("FROM users WHERE LOWER(email)")) {
      return { rows: [{ id: 42, email: "pat@example.com", password_hash: passwordHash }] };
    }
    if (text.includes("SELECT * FROM user_devices") && text.includes("device_id=$2 LIMIT 1")) {
      return { rows: [] };
    }
    if (text.includes("SELECT * FROM user_devices") && text.includes("device_status='active'")) {
      return { rows: [{ id: 1, device_id: "old-phone", device_token: null, platform: "android" }] };
    }
    if (text.includes("FROM device_transfer_packages p")) {
      return { rows: packageFound ? [{ id: "pkg-1" }] : [] };
    }
    return { rows: [], rowCount: 0 };
  };

  const resolved = require.resolve("../check_user");
  delete require.cache[resolved];
  try {
    const { handler } = require("../check_user");
    const res = await handler({
      httpMethod: "POST",
      body: JSON.stringify({
        email: "pat@example.com",
        password: "Password1!",
        device_id: "new-phone",
        platform: "android",
        replace: true,
        replacement_reason: "replaced",
        ...(transferCode ? { transfer_code: transferCode } : {}),
      }),
    });
    return { res, body: JSON.parse(res.body), calls };
  } finally {
    db.query = originalQuery;
    delete require.cache[resolved];
  }
}

const revokedOldPhone = (calls) =>
  calls.some((c) => /SET device_status=\$1, revoked_at=NOW\(\)/.test(c.sql));

test("a wrong transfer code is refused before the old phone is disabled", async () => {
  const { res, body, calls } = await loginWithTransferCode({
    transferCode: "WRNG-CODE",
    packageFound: false,
  });
  assert.equal(res.statusCode, 409);
  assert.equal(body.error, "TRANSFER_CODE_INVALID");
  assert.equal(revokedOldPhone(calls), false);

  const lookup = calls.find((c) => c.sql.includes("FROM device_transfer_packages p"));
  assert.equal(lookup.params[1], "WRNGC0DE", "lookup uses the normalized code");
});

test("a matching transfer code switches devices", async () => {
  const { res, body, calls } = await loginWithTransferCode({
    transferCode: "K7QM4TZP",
    packageFound: true,
  });
  assert.equal(res.statusCode, 200);
  assert.equal(body.success, true);
  assert.equal(revokedOldPhone(calls), true);
});

test("older apps without a code keep the previous any-package check", async () => {
  const { res, calls } = await loginWithTransferCode({ packageFound: true });
  assert.equal(res.statusCode, 200);
  const lookup = calls.find((c) => c.sql.includes("FROM device_transfer_packages p"));
  assert.equal(lookup.params[1], null);
});

test("current-phone recovery cannot replace an active device without matching installation proof", async () => {
  const passwordHash = await hashPassword("Password1!");
  const calls = [];
  const originalQuery = db.query;
  db.query = async (sql, params = []) => {
    const text = String(sql);
    calls.push({ sql: text, params });
    if (text.includes("FROM users WHERE LOWER(email)")) {
      return { rows: [{ id: 42, email: "pat@example.com", password_hash: passwordHash }] };
    }
    if (text.includes("FROM user_devices") && text.includes("device_token=$2")) {
      return { rows: [] };
    }
    if (text.includes("SELECT * FROM user_devices") && text.includes("device_id=$2 LIMIT 1")) {
      return { rows: [] };
    }
    if (text.includes("SELECT * FROM user_devices") && text.includes("device_status='active'")) {
      return { rows: [{ id: 1, device_id: "old-phone", device_token: "old-token" }] };
    }
    return { rows: [], rowCount: 0 };
  };

  const resolved = require.resolve("../check_user");
  delete require.cache[resolved];
  try {
    const { handler } = require("../check_user");
    const res = await handler({
      httpMethod: "POST",
      body: JSON.stringify({
        email: "pat@example.com",
        password: "Password1!",
        device_id: "new-phone",
        fcm_token: "new-token",
        recover_installation: true,
      }),
    });
    const body = JSON.parse(res.body);
    assert.equal(res.statusCode, 409);
    assert.equal(body.error, "INSTALLATION_RECOVERY_NOT_VERIFIED");
    assert.equal(revokedOldPhone(calls), false);
    assert.equal(calls.some((c) => c.sql.includes("authenticated_current_phone_confirmation")), false);
  } finally {
    db.query = originalQuery;
    delete require.cache[resolved];
  }
});
