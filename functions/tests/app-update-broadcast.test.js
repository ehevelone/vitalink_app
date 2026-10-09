const assert = require("node:assert/strict");
const test = require("node:test");

const db = require("../services/db");
const adminAuth = require("../_adminAuth");

async function runBroadcast({ admin = true, body, userRows, agentRows, recentSend = false, results }) {
  const sent = [];
  const calls = [];
  const originalQuery = db.query;
  const originalRequireAdmin = adminAuth.requireAdmin;
  const firebasePath = require.resolve("firebase-admin");
  const originalFirebase = require.cache[firebasePath];

  db.query = async (sql, params = []) => {
    const text = String(sql);
    calls.push({ sql: text, params });
    if (text.includes("FROM user_devices")) return { rows: userRows };
    if (text.includes("FROM agent_devices")) return { rows: agentRows };
    if (text.includes("FROM app_update_broadcasts")) return { rows: recentSend ? [{ sent_at: new Date() }] : [] };
    return { rows: [], rowCount: 0 };
  };
  adminAuth.requireAdmin = async () => (admin ? { admin: { id: 1 } } : { error: "Invalid session" });
  require.cache[firebasePath] = {
    id: firebasePath,
    filename: firebasePath,
    loaded: true,
    exports: {
      apps: [{}],
      messaging: () => ({
        sendEachForMulticast: async (message) => {
          sent.push(message);
          const responses = message.tokens.map((token) => results?.[token] || { success: true });
          return {
            successCount: responses.filter((r) => r.success).length,
            failureCount: responses.filter((r) => !r.success).length,
            responses,
          };
        },
      }),
    },
  };

  const modulePath = require.resolve("../send_app_update_notification");
  delete require.cache[modulePath];
  try {
    const { handler } = require("../send_app_update_notification");
    const res = await handler({
      httpMethod: "POST",
      headers: { "x-admin-session": "admin-token" },
      body: JSON.stringify(body),
    });
    return { res, body: JSON.parse(res.body), sent, calls };
  } finally {
    db.query = originalQuery;
    adminAuth.requireAdmin = originalRequireAdmin;
    if (originalFirebase) require.cache[firebasePath] = originalFirebase;
    else delete require.cache[firebasePath];
    delete require.cache[modulePath];
  }
}

test("only admins can send the update broadcast", async () => {
  const { res, sent } = await runBroadcast({
    admin: false,
    body: {},
    userRows: [{ id: 1, device_token: "client-phone" }],
    agentRows: [],
  });
  assert.equal(res.statusCode, 401);
  assert.equal(sent.length, 0);
});

test("preview counts phones without sending anything", async () => {
  const { body, sent } = await runBroadcast({
    body: { dryRun: true },
    userRows: [{ id: 1, device_token: "a" }, { id: 2, device_token: "b" }],
    agentRows: [{ id: 9, device_token: "c" }],
  });
  assert.equal(body.devicesTargeted, 3);
  assert.equal(sent.length, 0);
});

test("every phone gets one visible notification that old app versions display", async () => {
  const { body, sent } = await runBroadcast({
    body: {},
    userRows: [{ id: 1, device_token: "shared-phone" }, { id: 2, device_token: "client-only" }],
    agentRows: [{ id: 9, device_token: "shared-phone" }, { id: 10, device_token: "agent-only" }],
  });
  assert.equal(body.success, true);
  assert.equal(body.devicesTargeted, 3, "a dual-role phone is notified once");
  assert.equal(sent.length, 1);
  const message = sent[0];
  assert.deepEqual(message.tokens.sort(), ["agent-only", "client-only", "shared-phone"]);
  assert.ok(message.notification.title, "system-displayed notification for closed/old apps");
  assert.equal(message.data.route, "/update_app");
  assert.equal(message.android.notification.channelId, "vitalink_high_importance");
});

test("uninstalled phones are cleaned up after the send", async () => {
  const { body, calls } = await runBroadcast({
    body: {},
    userRows: [{ id: 1, device_token: "gone-client" }],
    agentRows: [{ id: 9, device_token: "gone-agent" }],
    results: {
      "gone-client": { success: false, error: { code: "messaging/registration-token-not-registered" } },
      "gone-agent": { success: false, error: { code: "messaging/registration-token-not-registered" } },
    },
  });
  assert.equal(body.uninstalledRemoved, 2);
  assert.ok(calls.some((c) => c.sql.includes("SET device_token='NO_TOKEN'") && c.params[0] === 1));
  assert.ok(calls.some((c) => c.sql.includes("DELETE FROM agent_devices") && c.params[0] === 9));
});

test("a second send within the cooldown is refused unless forced", async () => {
  const blocked = await runBroadcast({
    body: {},
    userRows: [{ id: 1, device_token: "a" }],
    agentRows: [],
    recentSend: true,
  });
  assert.equal(blocked.res.statusCode, 429);
  assert.equal(blocked.sent.length, 0);

  const forced = await runBroadcast({
    body: { force: true },
    userRows: [{ id: 1, device_token: "a" }],
    agentRows: [],
    recentSend: true,
  });
  assert.equal(forced.res.statusCode, 200);
  assert.equal(forced.sent.length, 1);
});

test("the platform filter limits the send to one store's phones", async () => {
  const { calls } = await runBroadcast({
    body: { platform: "ios", dryRun: true },
    userRows: [],
    agentRows: [],
  });
  const userQuery = calls.find((c) => c.sql.includes("FROM user_devices"));
  assert.deepEqual(userQuery.params, ["ios"]);
});

test("phones set to Spanish get the update notice in Spanish", async () => {
  const { body, sent } = await runBroadcast({
    body: { force: true },
    userRows: [
      { id: 1, device_token: "english-phone" },
      { id: 2, device_token: "spanish-phone", app_language: "es" },
    ],
    agentRows: [{ id: 9, device_token: "spanish-agent", app_language: "es" }],
  });
  assert.equal(body.successCount, 3);
  const spanish = sent.find((message) => message.tokens.includes("spanish-phone"));
  const english = sent.find((message) => message.tokens.includes("english-phone"));
  assert.deepEqual(spanish.tokens.sort(), ["spanish-agent", "spanish-phone"]);
  assert.match(spanish.notification.title, /actualización de VitaLink/);
  assert.equal(spanish.data.title, spanish.notification.title);
  assert.equal(english.notification.title, "VitaLink Update Available");
});
