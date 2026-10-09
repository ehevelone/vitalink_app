const assert = require("node:assert/strict");
const test = require("node:test");

const db = require("../services/db");
const userAuth = require("../services/user-auth");

// Loads a handler with db.query / db.connect / verifyUserSession replaced.
// Handlers destructure verifyUserSession at require time, so the stub must be
// in place before the (re)require.
async function withHandler(modulePath, { query, connect, session = false }, run) {
  const originalQuery = db.query;
  const originalConnect = db.connect;
  const originalVerify = userAuth.verifyUserSession;
  const calls = [];

  db.query = async (sql, params = []) => {
    calls.push({ sql: String(sql), params });
    return query ? query(String(sql), params) : { rows: [], rowCount: 0 };
  };
  if (connect) db.connect = connect;
  userAuth.verifyUserSession = async (...args) =>
    typeof session === "function" ? session(...args) : session;

  const resolved = require.resolve(modulePath);
  delete require.cache[resolved];
  try {
    const { handler } = require(modulePath);
    await run(handler, calls);
  } finally {
    db.query = originalQuery;
    db.connect = originalConnect;
    userAuth.verifyUserSession = originalVerify;
    delete require.cache[resolved];
  }
}

const post = (body) => ({ httpMethod: "POST", headers: {}, body: JSON.stringify(body) });
const parse = (res) => JSON.parse(res.body || "{}");

// ---------------------------------------------------------------------------
// C1: profile updates require the caller's own session
// ---------------------------------------------------------------------------

test("update_user_profile rejects a request without a valid session", async () => {
  await withHandler("../update_user_profile", { session: false }, async (handler, calls) => {
    const res = await handler(post({
      currentEmail: "victim@example.com",
      userId: "7",
      password: "attacker-chosen",
    }));
    assert.equal(res.statusCode, 403);
    assert.ok(!calls.some((c) => /UPDATE\s+users/i.test(c.sql)), "no user row may be updated");
  });
});

test("update_user_profile rejects an email that does not belong to the session user", async () => {
  await withHandler("../update_user_profile", {
    session: true,
    query: (sql) => (sql.includes("SELECT id FROM users WHERE id = $1 AND LOWER(email)")
      ? { rows: [] }
      : { rows: [] }),
  }, async (handler, calls) => {
    const res = await handler(post({
      currentEmail: "someone-else@example.com",
      userId: "7",
      sessionToken: "s",
      password: "new-password",
    }));
    assert.equal(res.statusCode, 403);
    assert.ok(!calls.some((c) => /UPDATE\s+users/i.test(c.sql)));
  });
});

test("update_user_profile updates by user id and refuses a duplicate email", async () => {
  await withHandler("../update_user_profile", {
    session: true,
    query: (sql) => {
      if (sql.includes("AND LOWER(email) = LOWER($2)")) return { rows: [{ id: 7 }] };
      if (sql.includes("AND id <> $2")) return { rows: [{ id: 99 }] };
      return { rows: [] };
    },
  }, async (handler, calls) => {
    const res = await handler(post({
      currentEmail: "owner@example.com",
      userId: "7",
      sessionToken: "s",
      email: "Taken@Example.com",
    }));
    assert.equal(res.statusCode, 409);
    assert.ok(!calls.some((c) => /UPDATE\s+users/i.test(c.sql)));
  });

  await withHandler("../update_user_profile", {
    session: true,
    query: (sql) => {
      if (sql.includes("AND LOWER(email) = LOWER($2)")) return { rows: [{ id: 7 }] };
      if (sql.includes("AND id <> $2")) return { rows: [] };
      if (/UPDATE\s+users/i.test(sql)) return { rows: [{ id: 7, email: "new@example.com" }] };
      return { rows: [] };
    },
  }, async (handler, calls) => {
    const res = await handler(post({
      currentEmail: "owner@example.com",
      userId: "7",
      sessionToken: "s",
      email: "New@Example.com",
    }));
    assert.equal(res.statusCode, 200);
    const update = calls.find((c) => /UPDATE\s+users/i.test(c.sql));
    assert.match(update.sql, /WHERE id = \$\d+/);
    assert.ok(update.params.includes("new@example.com"), "email is stored lowercased");
    assert.equal(update.params[update.params.length - 1], "7");
  });
});

// ---------------------------------------------------------------------------
// C2 / vl-register-purchase: retired endpoints never touch the database
// ---------------------------------------------------------------------------

for (const retired of ["../request_delete", "../vl-register-purchase"]) {
  test(`${retired.slice(3)} is retired and performs no database work`, async () => {
    await withHandler(retired, { session: true }, async (handler, calls) => {
      const res = await handler(post({ email: "agent@example.com", name: "x" }));
      assert.equal(res.statusCode, 410);
      assert.equal(calls.length, 0);
    });
  });
}

// ---------------------------------------------------------------------------
// C5: formerly open endpoints now require a session
// ---------------------------------------------------------------------------

for (const [modulePath, body] of [
  ["../get_user_agent", { email: "client@example.com", userId: "7" }],
  ["../mark_reviewed", { email: "client@example.com", userId: "7" }],
  ["../send_form_email", {
    app_user_id: "7",
    agent: { email: "agent@example.com", name: "Agent" },
    attachments: [],
    user: "client@example.com",
  }],
]) {
  test(`${modulePath.slice(3)} refuses requests without a valid session`, async () => {
    await withHandler(modulePath, { session: false }, async (handler, calls) => {
      const res = await handler(post(body));
      assert.equal(res.statusCode, 403);
      assert.ok(!calls.some((c) => /UPDATE\s+users/i.test(c.sql)));
    });
  });
}

// ---------------------------------------------------------------------------
// R1: revoked phones learn they are revoked even after their session is gone
// ---------------------------------------------------------------------------

test("check_device_status reports revocation without a session", async () => {
  await withHandler("../check_device_status", {
    session: false,
    query: (sql) => (sql.includes("FROM user_devices")
      ? { rows: [{ device_status: "replaced", revocation_reason: "lost", revoked_at: null }] }
      : { rows: [] }),
  }, async (handler) => {
    const res = await handler(post({ userId: "7", deviceId: "old-phone" }));
    assert.equal(res.statusCode, 200);
    const body = parse(res);
    assert.equal(body.active, false);
    assert.equal(body.reason, "lost");
  });
});

test("check_device_status requires a session for active or unknown devices", async () => {
  await withHandler("../check_device_status", {
    session: false,
    query: (sql) => (sql.includes("FROM user_devices")
      ? { rows: [{ device_status: "active" }] }
      : { rows: [] }),
  }, async (handler) => {
    const res = await handler(post({ userId: "7", deviceId: "phone" }));
    assert.equal(res.statusCode, 403);
  });

  await withHandler("../check_device_status", { session: true }, async (handler) => {
    const res = await handler(post({ userId: "7", deviceId: "never-registered" }));
    assert.equal(res.statusCode, 200);
    assert.equal(parse(res).active, true, "a missing row is not treated as revoked");
  });
});

// ---------------------------------------------------------------------------
// C4: personal access codes are claimed once, atomically, by the purchaser
// ---------------------------------------------------------------------------

function registrationEvent(email) {
  return post({
    firstName: "Pat",
    lastName: "Client",
    email,
    phone: "5555550100",
    password: "Password1!",
    promoCode: "VL-CODE-1",
    platform: "android",
    deviceId: "device-1",
  });
}

function registrationDb({ codeEmail, claimSucceeds }) {
  const txCalls = [];
  const client = {
    query: async (sql) => {
      txCalls.push(String(sql));
      if (String(sql).includes("UPDATE activation_codes") && String(sql).includes("redeemed=false")) {
        return claimSucceeds ? { rows: [{ code: "VL-CODE-1" }] } : { rows: [] };
      }
      if (/INSERT INTO users/i.test(String(sql))) {
        return { rows: [{ id: 501, email: "pat@example.com" }] };
      }
      return { rows: [] };
    },
    release: () => {},
  };
  return {
    txCalls,
    connect: async () => client,
    query: (sql) => {
      if (sql.includes("FROM agents WHERE unlock_code")) return { rows: [] };
      if (sql.includes("FROM activation_codes WHERE code")) {
        return { rows: [{ code: "VL-CODE-1", email: codeEmail, redeemed: false }] };
      }
      if (/INSERT INTO users/i.test(sql)) return { rows: [{ id: 501, email: "pat@example.com" }] };
      return { rows: [] };
    },
  };
}

test("register_user rejects a personal code bought with a different email", async () => {
  const fake = registrationDb({ codeEmail: "buyer@example.com", claimSucceeds: true });
  await withHandler("../register_user", { query: fake.query, connect: fake.connect }, async (handler, calls) => {
    const body = parse(await handler(registrationEvent("someone-else@example.com")));
    assert.equal(body.success, false);
    assert.match(body.error, /email address that purchased/i);
    assert.ok(!calls.some((c) => /INSERT INTO users/i.test(c.sql)));
    assert.equal(fake.txCalls.length, 0);
  });
});

test("register_user creates no account when the code was claimed concurrently", async () => {
  const fake = registrationDb({ codeEmail: "pat@example.com", claimSucceeds: false });
  await withHandler("../register_user", { query: fake.query, connect: fake.connect }, async (handler) => {
    const body = parse(await handler(registrationEvent("pat@example.com")));
    assert.equal(body.success, false);
    assert.match(body.error, /already been used/i);
    assert.ok(fake.txCalls.includes("ROLLBACK"));
    assert.ok(!fake.txCalls.some((sql) => /INSERT INTO users/i.test(sql)));
  });
});

test("register_user claims the code and creates the user in one transaction", async () => {
  const fake = registrationDb({ codeEmail: "pat@example.com", claimSucceeds: true });
  await withHandler("../register_user", { query: fake.query, connect: fake.connect }, async (handler) => {
    const body = parse(await handler(registrationEvent("pat@example.com")));
    assert.equal(body.success, true);
    const begin = fake.txCalls.indexOf("BEGIN");
    const claim = fake.txCalls.findIndex((sql) => sql.includes("redeemed=false"));
    const insert = fake.txCalls.findIndex((sql) => /INSERT INTO users/i.test(sql));
    const commit = fake.txCalls.indexOf("COMMIT");
    assert.ok(begin >= 0 && begin < claim && claim < insert && insert < commit);
  });
});
