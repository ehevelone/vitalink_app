const db = require("./services/db");
const admin = require("firebase-admin");
const { verifyAgentSession } = require("./services/agent-auth");
const {
  MESSAGING_CONSENT_VERSION,
  ensureAccountAccessSchema,
} = require("./services/account-access");
const {
  deviceLanguage,
  ensureLanguageColumns,
  notificationText,
  sendLocalizedMulticast,
} = require("./services/notification-language");

/* INIT FIREBASE (SAFE ENV ONLY) */
if (!admin.apps.length) {
  try {

    if (
      !process.env.FIREBASE_PROJECT_ID ||
      !process.env.FIREBASE_CLIENT_EMAIL ||
      !process.env.FIREBASE_PRIVATE_KEY
    ) {
      console.error("❌ FIREBASE ENV MISSING");
      throw new Error("Firebase ENV not set");
    }

    let privateKey = process.env.FIREBASE_PRIVATE_KEY;

    if (privateKey.includes("\\n")) {
      privateKey = privateKey.replace(/\\n/g, "\n");
    }

    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: privateKey
      })
    });

    console.log("✅ Firebase initialized");

  } catch (err) {
    console.error("🔥 Firebase init crash:", err);
    throw err;
  }
}

/* RESPONSE HELPER */
function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

/* INVALID TOKEN DETECTION */
function isInvalidTokenError(err) {
  const msg = (err?.message || "").toLowerCase();
  const code = (err?.code || "").toLowerCase();

  return (
    msg.includes("requested entity was not found") ||
    msg.includes("registration-token-not-registered") ||
    code.includes("registration-token-not-registered") ||
    code.includes("invalid-argument") ||
    msg.includes("invalid argument")
  );
}

async function ensureDeviceDeliveryColumns() {
  await db.query(`
    ALTER TABLE user_devices
    ADD COLUMN IF NOT EXISTS push_status TEXT,
    ADD COLUMN IF NOT EXISTS device_status TEXT NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS last_push_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_push_success_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_push_failure_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_push_error TEXT
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS agent_message_events (
      id BIGSERIAL PRIMARY KEY,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      campaign TEXT NOT NULL,
      eligible_user_count INTEGER NOT NULL DEFAULT 0,
      devices_targeted INTEGER NOT NULL DEFAULT 0,
      success_count INTEGER NOT NULL DEFAULT 0,
      failure_count INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

async function recordDeliveryResults(devices, response) {
  const results = response?.responses || [];

  for (let i = 0; i < devices.length; i++) {
    const device = devices[i];
    const result = results[i];

    if (!result) continue;

    if (result.success) {
      await db.query(
        `
        UPDATE user_devices
        SET push_status='delivered',
            last_push_at=NOW(),
            last_push_success_at=NOW(),
            last_push_error=NULL
        WHERE id=$1
        `,
        [device.deviceRowId]
      );
      continue;
    }

    const errorText =
      result.error?.code ||
      result.error?.message ||
      "Push failed";

    const invalidToken = isInvalidTokenError(result.error);

    await db.query(
      `
      UPDATE user_devices
      SET push_status=$1,
          last_push_at=NOW(),
          last_push_failure_at=NOW(),
          last_push_error=$2,
          device_token=CASE WHEN $3 THEN 'NO_TOKEN' ELSE device_token END
      WHERE id=$4
      `,
      [
        invalidToken ? "invalid" : "failed",
        errorText,
        invalidToken,
        device.deviceRowId,
      ]
    );
  }
}

/* CAMPAIGN TIMING */
function pickCampaign(now = new Date()) {
  const m = now.getMonth() + 1;
  const d = now.getDate();

  if (m === 9) return "PREP";
  if ((m === 10) || (m === 11) || (m === 12 && d <= 7)) return "AEP";
  if ((m === 12 && d >= 8) || m === 1 || m === 2 || m === 3) return "OEP";

  return "GENERAL";
}

/* CAMPAIGN MESSAGES */
function campaignText(campaign, agentName, language = "en") {
  const text = (key, vars) => notificationText(key, language, vars);
  const title = text("messageFrom", { name: agentName });

  if (campaign === "PREP") {
    return { title, body: text("campaignPrep"), route: "/authorization_form" };
  }

  if (campaign === "AEP") {
    return { title, body: text("campaignAep"), route: "/authorization_form" };
  }

  if (campaign === "OEP") {
    return { title, body: text("campaignOep"), route: "/authorization_form" };
  }

  // 🔥 NEW UPDATE NOTIFICATION
  if (campaign === "UPDATE") {
    return {
      title: text("appUpdatedTitle"),
      body: text("appUpdatedBody"),
      route: "/update_app",
    };
  }

  return { title, body: text("campaignGeneral"), route: "/authorization_form" };
}

/* SEASON LOGIC */
function getCycleStart(now = new Date()) {
  const y = now.getFullYear();
  const m = now.getMonth() + 1;

  if (m >= 9) return new Date(y, 8, 1);
  if (m <= 3) return new Date(y - 1, 8, 1);

  return new Date(y, 3, 1);
}

/* HANDLER */
exports.handler = async (event) => {

  console.log("=== SEND NOTIFICATION START ===");

  try {

    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureDeviceDeliveryColumns();
    await ensureLanguageColumns();
    await ensureAccountAccessSchema();

    let body = {};

    try {
      body = event.isBase64Encoded
        ? JSON.parse(Buffer.from(event.body, "base64").toString("utf8"))
        : JSON.parse(event.body || "{}");
    } catch (err) {
      return reply(400, { success: false, error: "Invalid request body" });
    }

    const { agentEmail } = body;

    if (!agentEmail) {
      return reply(400, { success: false, error: "Missing agentEmail" });
    }

    const authenticatedAgent = await verifyAgentSession({
      agentEmail: agentEmail.trim(),
      token: body.agentSessionToken,
    });
    if (!authenticatedAgent) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const forcedCampaign =
      typeof body.campaign === "string"
        ? body.campaign.trim().toUpperCase()
        : null;

    const agentRes = await db.query(
      "SELECT id, name FROM agents WHERE LOWER(email)=LOWER($1) LIMIT 1",
      [agentEmail.trim()]
    );

    if (!agentRes.rows.length) {
      return reply(404, { success: false, error: "Agent not found" });
    }

    const agent = agentRes.rows[0];
    if (Number(authenticatedAgent.id) !== Number(agent.id)) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const now = new Date();
    const campaign = forcedCampaign || pickCampaign(now);
    const cycleStart = getCycleStart(now);

    const eligibleSql = `
      SELECT
        ud.id AS device_row_id,
        ud.device_token AS device_token,
        ud.user_id AS user_id,
        ud.app_language AS app_language
      FROM user_devices ud
      JOIN users u ON u.id = ud.user_id
      WHERE u.agent_id = $1
      AND u.relationship_status = 'confirmed_client'
      AND u.messaging_consent_status = 'granted'
      AND u.messaging_consent_version = $2
      AND ud.device_status = 'active'
      AND ud.device_token IS NOT NULL
      AND TRIM(ud.device_token) <> ''
      AND TRIM(ud.device_token) <> 'NO_TOKEN'
    `;

    const devicesRes = await db.query(eligibleSql, [agent.id, MESSAGING_CONSENT_VERSION]);

    if (!devicesRes.rows.length) {
      await db.query(
        `INSERT INTO agent_message_events
          (agent_id, campaign, eligible_user_count)
         VALUES ($1,$2,0)`,
        [agent.id, campaign]
      );
      return reply(200, { success: true, message: "No eligible devices" });
    }

    const seen = new Set();
    const devices = [];

    for (const row of devicesRes.rows) {
      const token = String(row.device_token || "").trim();

      if (!token || seen.has(token)) continue;

      seen.add(token);

      devices.push({
        deviceRowId: row.device_row_id,
        userId: row.user_id,
        token,
        language: deviceLanguage(row),
      });
    }

    const tokens = devices.map(d => d.token);

    // Each phone gets the message in its own app language.
    const response = await sendLocalizedMulticast(
      admin.messaging(),
      devices,
      (language, languageTokens) => {
        const notif = campaignText(campaign, agent.name, language);
        return {
          tokens: languageTokens,
          notification: {
            title: notif.title,
            body: notif.body,
          },
          android: {
            priority: "high",
          },
          data: {
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            route: notif.route,
          },
        };
      }
    );

    await recordDeliveryResults(devices, response);
    await db.query(
      `INSERT INTO agent_message_events
        (agent_id, campaign, eligible_user_count, devices_targeted,
         success_count, failure_count)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [
        agent.id,
        campaign,
        new Set(devices.map((device) => device.userId)).size,
        tokens.length,
        response?.successCount ?? 0,
        response?.failureCount ?? 0,
      ]
    );

    return reply(200, {
      success: true,
      devicesTargeted: tokens.length,
      successCount: response?.successCount ?? 0,
      failureCount: response?.failureCount ?? 0,
      needsContactCount: response?.failureCount ?? 0,
    });

  } catch (err) {
    console.error("SEND NOTIFICATION ERROR", err);

    return reply(500, {
      success: false,
      error: "Server error while sending notifications",
    });
  }
};
