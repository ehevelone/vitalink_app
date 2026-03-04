// functions/send_notification.js
const db = require("./services/db");
const admin = require("firebase-admin");

let serviceAccount = {};
try {
  serviceAccount = JSON.parse(process.env.FCM_SERVICE_ACCOUNT || "{}");
} catch (e) {
  console.error("❌ Invalid FCM_SERVICE_ACCOUNT JSON");
}

if (!admin.apps.length && serviceAccount.project_id) {
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

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST")
      return reply(405, { success: false, error: "Method Not Allowed" });

    const body = JSON.parse(event.body || "{}");
    const { agentEmail } = body;

    if (!agentEmail)
      return reply(400, { success: false, error: "Missing agentEmail" });

    const agentRes = await db.query(
      `SELECT id, name FROM agents WHERE LOWER(email)=LOWER($1) LIMIT 1`,
      [agentEmail.trim()]
    );

    if (!agentRes.rows.length)
      return reply(404, { success: false, error: "Agent not found" });

    const agent = agentRes.rows[0];
    const currentYear = new Date().getFullYear();

    // 🔑 Only users NOT reviewed this year
    const usersRes = await db.query(
      `
      SELECT id
      FROM users
      WHERE agent_id = $1
      AND (
            last_review_year IS NULL
            OR last_review_year < $2
          )
      `,
      [agent.id, currentYear]
    );

    if (!usersRes.rows.length) {
      return reply(200, {
        success: true,
        message: "All users already reviewed this year",
      });
    }

    const userIds = usersRes.rows.map((u) => u.id);

    const devicesRes = await db.query(
      `
      SELECT id, device_token
      FROM user_devices
      WHERE user_id = ANY($1::int[])
      AND device_token IS NOT NULL
      `,
      [userIds]
    );

    if (!devicesRes.rows.length)
      return reply(404, { success: false, error: "No registered devices" });

    const cleaned = devicesRes.rows
      .map((d) => ({
        id: d.id,
        token: String(d.device_token || "").trim(),
      }))
      .filter((d) => d.token && d.token !== "NO_TOKEN");

    if (!cleaned.length)
      return reply(404, {
        success: false,
        error: "No valid device tokens",
      });

    const seen = new Set();
    const devices = [];
    for (const d of cleaned) {
      if (seen.has(d.token)) continue;
      seen.add(d.token);
      devices.push(d);
    }

    const tokens = devices.map((d) => d.token);

    const message = {
      tokens,
      notification: {
        title: `Message from ${agent.name || "Your Agent"}`,
        body: "⏰ Time to send your Medicare information!",
      },
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

    const response =
      await admin.messaging().sendEachForMulticast(message);

    const invalidTokenIds = [];

    for (let i = 0; i < response.responses.length; i++) {
      const r = response.responses[i];
      const device = devices[i];

      if (!r.success && isInvalidTokenError(r.error)) {
        invalidTokenIds.push(device.id);
      }
    }

    if (invalidTokenIds.length) {
      await db.query(
        `DELETE FROM user_devices WHERE id = ANY($1::int[])`,
        [invalidTokenIds]
      );
    }

    return reply(200, {
      success: true,
      successCount: response.successCount,
      totalDevices: tokens.length,
    });
  } catch (err) {
    console.error("❌ send_notification error:", err);
    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};