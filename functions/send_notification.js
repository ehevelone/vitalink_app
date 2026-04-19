const db = require("./services/db");
const admin = require("firebase-admin");

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

/* CAMPAIGN TIMING (YOUR VERSION) */
function pickCampaign(now = new Date()) {
  const m = now.getMonth() + 1;
  const d = now.getDate();

  if (m === 9) return "PREP";

  if ((m === 10) || (m === 11) || (m === 12 && d <= 7)) return "AEP";

  if ((m === 12 && d >= 8) || m === 1 || m === 2 || m === 3) return "OEP";

  return "GENERAL";
}

/* CAMPAIGN MESSAGES */
function campaignText(campaign, agentName) {
  const name = agentName || "Your Agent";

  if (campaign === "PREP") {
    return {
      title: `Message from ${name}`,
      body: "Medicare enrollment is approaching. Please tap here to securely send your information before your upcoming appointment.",
    };
  }

  if (campaign === "AEP") {
    return {
      title: `Message from ${name}`,
      body: "It's time for your Medicare Enrollment Review! Please tap here to securely send your updated information to your agent.",
    };
  }

  if (campaign === "OEP") {
    return {
      title: `Message from ${name}`,
      body: "There’s still time to review your Medicare coverage. Tap here to securely send your updated information to your agent.",
    };
  }

  return {
    title: `Message from ${name}`,
    body: "Tap here to securely send your Medicare information so your agent can keep your coverage up to date.",
  };
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

    const cooldownDays =
      Number.isFinite(Number(body.cooldownDays))
        ? Number(body.cooldownDays)
        : 14;

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

    const now = new Date();

    const campaign = forcedCampaign || pickCampaign(now);

    const cycleStart = getCycleStart(now);

    const eligibleSql = `
      SELECT
        ud.id AS device_row_id,
        ud.device_token AS device_token,
        ud.user_id AS user_id
      FROM user_devices ud
      JOIN users u ON u.id = ud.user_id
      WHERE u.agent_id = $1
      AND ud.device_token IS NOT NULL
      AND TRIM(ud.device_token) <> ''
      AND TRIM(ud.device_token) <> 'NO_TOKEN'
      -- cooldown removed for testing
      AND (
        u.last_reviewed IS NULL
        OR u.last_reviewed < $2::timestamptz
      )
    `;

    const devicesRes = await db.query(eligibleSql, [
      agent.id,
      cycleStart.toISOString(),
    ]);

    if (!devicesRes.rows.length) {
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
      });
    }

    const tokens = devices.map(d => d.token);

    const notif = campaignText(campaign, agent.name);

    const message = {
      tokens,
      notification: notif,
      android: {
        priority: "high",
        notification: {
          channelId: "high_importance_channel",
          sound: "default",
        },
      },
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        route: "/authorization_form",
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    return reply(200, {
      success: true,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });

  } catch (err) {
    console.error("SEND NOTIFICATION ERROR", err);

    return reply(500, {
      success: false,
      error: "Server error while sending notifications",
    });
  }
};