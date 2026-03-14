// functions/send_notification.js

const db = require("./services/db");
const admin = require("firebase-admin");

const serviceAccount = require("./firebase-service-account.json");

// ✅ Initialize Firebase once
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

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

// -----------------------------
// Campaign selection
// -----------------------------
function pickCampaign(now = new Date()) {
  const m = now.getMonth() + 1;
  const d = now.getDate();

  const inPrep = (m === 9) || (m === 10 && d <= 14);
  const inAep = (m === 10 && d >= 15) || (m === 11) || (m === 12 && d <= 7);
  const inOep = (m === 1) || (m === 2) || (m === 3);

  if (inAep) return "AEP";
  if (inOep) return "OEP";
  if (inPrep) return "PREP";

  return "OFF";
}

function campaignText(campaign, agentName) {

  const name = agentName || "Your Agent";

  if (campaign === "PREP") {
    return {
      title: `Message from ${name}`,
      body: "📋 Please complete your profile & send your Medicare info so we can check plans before your appointment.",
    };
  }

  return {
    title: `Message from ${name}`,
    body: "⏰ Time to send your Medicare information!",
  };
}

function getCycleStartApr1(now = new Date()) {

  const y = now.getFullYear();
  const apr1 = new Date(y, 3, 1, 0, 0, 0, 0);

  if (now >= apr1) return apr1;

  return new Date(y - 1, 3, 1, 0, 0, 0, 0);
}

exports.handler = async (event) => {

  try {

    if (event.httpMethod === "OPTIONS") return reply(200, {});

    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    let body = {};

    try {

      body = event.isBase64Encoded
        ? JSON.parse(Buffer.from(event.body, "base64").toString("utf8"))
        : JSON.parse(event.body || "{}");

    } catch {

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
      `SELECT id, name FROM agents WHERE LOWER(email)=LOWER($1) LIMIT 1`,
      [agentEmail.trim()]
    );

    if (!agentRes.rows.length) {
      return reply(404, { success: false, error: "Agent not found" });
    }

    const agent = agentRes.rows[0];

    const now = new Date();

    const campaign = forcedCampaign || pickCampaign(now);

    if (campaign === "OFF") {
      return reply(200, {
        success: true,
        message: "Outside PREP/AEP/OEP window",
      });
    }

    const year = now.getFullYear();

    const cycleStart = getCycleStartApr1(now);

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
      AND (
        u.last_notified_at IS NULL
        OR u.last_notified_at < NOW() - ($2::text || ' days')::interval
      )
      AND (
        u.last_reviewed IS NULL
        OR u.last_reviewed < $5::timestamptz
      )
      AND (
        CASE
          WHEN $3 = 'PREP' THEN
            (COALESCE(u.profile_complete, FALSE) = FALSE)
            OR (COALESCE(u.last_plan_check_year,0) < $4)
          WHEN $3 = 'AEP' THEN
            (COALESCE(u.last_review_year,0) < $4)
          WHEN $3 = 'OEP' THEN
            (COALESCE(u.last_review_year,0) < $4)
          ELSE FALSE
        END
      )
    `;

    const devicesRes = await db.query(eligibleSql, [
      agent.id,
      String(cooldownDays),
      campaign,
      year,
      cycleStart.toISOString(),
    ]);

    if (!devicesRes.rows.length) {
      return reply(200, {
        success: true,
        message: `No eligible devices to notify`,
        campaign,
      });
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

    const invalidDeviceRowIds = [];
    const invalidTokens = [];
    const successUserIds = new Set();

    for (let i = 0; i < response.responses.length; i++) {

      const r = response.responses[i];
      const device = devices[i];

      if (r.success) {
        successUserIds.add(device.userId);
      } else if (isInvalidTokenError(r.error)) {
        invalidDeviceRowIds.push(device.deviceRowId);
        invalidTokens.push(device.token);
      }

    }

    if (successUserIds.size) {

      await db.query(
        `
        UPDATE users
        SET last_notified_at = NOW(),
            last_notified_campaign = $1
        WHERE id = ANY($2::int[])
        `,
        [campaign, Array.from(successUserIds)]
      );

    }

    if (invalidDeviceRowIds.length) {

      await db.query(
        `DELETE FROM user_devices WHERE id = ANY($1::int[])`,
        [invalidDeviceRowIds]
      );

    }

    return reply(200, {

      success: true,
      campaign,
      cooldownDays,
      totalDevices: tokens.length,
      successCount: response.successCount,
      failureCount: response.failureCount,
      notifiedUsers: successUserIds.size,
      removedInvalidTokens: invalidTokens.length,

    });

  } catch (err) {

    console.error("send_notification error:", err);

    return reply(500, {
      success: false,
      error: "Server error while sending notifications",
    });

  }

};