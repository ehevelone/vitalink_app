// functions/send_notification.js
const db = require("./services/db");
const admin = require("firebase-admin");

let serviceAccount = {};
try {
  serviceAccount = JSON.parse(process.env.FCM_SERVICE_ACCOUNT || "{}");
} catch (e) {
  console.error("❌ Invalid FCM_SERVICE_ACCOUNT JSON");
}

// ✅ Initialize Firebase once
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

  // Firebase Admin SDK error patterns (both message + code)
  return (
    msg.includes("requested entity was not found") ||
    msg.includes("registration-token-not-registered") ||
    code.includes("registration-token-not-registered") ||
    code.includes("invalid-argument") || // sometimes shows up for malformed tokens
    msg.includes("invalid argument")
  );
}

exports.handler = async (event) => {
  try {
    // ✅ CORS preflight
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    // ✅ Safe body parsing
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

    // ✅ Get agent
    const agentRes = await db.query(
      `SELECT id, name FROM agents WHERE LOWER(email) = LOWER($1) LIMIT 1`,
      [agentEmail.trim()]
    );

    if (!agentRes.rows.length) {
      return reply(404, { success: false, error: "Agent not found" });
    }

    const agent = agentRes.rows[0];

    // ✅ Get users linked to agent
    const usersRes = await db.query(`SELECT id FROM users WHERE agent_id = $1`, [
      agent.id,
    ]);

    if (!usersRes.rows.length) {
      return reply(404, {
        success: false,
        error: "No users linked to this agent",
      });
    }

    const userIds = usersRes.rows.map((u) => u.id);

    // ✅ Get device tokens (+ id so we can delete precisely if needed)
    const devicesRes = await db.query(
      `
      SELECT id, device_token
      FROM user_devices
      WHERE user_id = ANY($1::int[])
        AND device_token IS NOT NULL
      `,
      [userIds]
    );

    if (!devicesRes.rows.length) {
      return reply(404, { success: false, error: "No registered devices" });
    }

    // ✅ Normalize + filter junk
    const cleaned = devicesRes.rows
      .map((d) => ({
        id: d.id,
        token: String(d.device_token || "").trim(),
      }))
      .filter((d) => d.token && d.token !== "NO_TOKEN");

    if (!cleaned.length) {
      return reply(404, {
        success: false,
        error: "No valid device tokens (only NO_TOKEN/blank)",
      });
    }

    // Deduplicate tokens (keep first occurrence)
    const seen = new Set();
    const devices = [];
    for (const d of cleaned) {
      if (seen.has(d.token)) continue;
      seen.add(d.token);
      devices.push(d);
    }

    const tokens = devices.map((d) => d.token);

    // 🔔 REAL NOTIFICATION
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

      // NOTE: iOS foreground handling requires app-side presentation settings.
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        route: "/authorization_form",
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    // ✅ IMPORTANT: DO NOT use forEach(async...). Await cleanup before returning.
    console.log("=== PUSH DEBUG ===");
    console.log("SuccessCount:", response.successCount);
    console.log("FailureCount:", response.failureCount);

    const invalidTokenIds = [];
    const invalidTokens = [];

    for (let i = 0; i < response.responses.length; i++) {
      const r = response.responses[i];
      const device = devices[i];

      console.log("Token:", device.token);
      console.log("Success:", r.success);

      if (!r.success) {
        console.log("Error:", r.error?.message);

        if (isInvalidTokenError(r.error)) {
          invalidTokenIds.push(device.id);
          invalidTokens.push(device.token);
        }
      }
    }

    // ✅ Delete invalid tokens from DB so the system self-heals
    if (invalidTokenIds.length) {
      try {
        await db.query(
          `DELETE FROM user_devices WHERE id = ANY($1::int[])`,
          [invalidTokenIds]
        );
        console.log("🧹 Removed invalid tokens count:", invalidTokenIds.length);
      } catch (e) {
        console.error("❌ Failed deleting invalid tokens:", e);
      }
    }

    return reply(200, {
      success: true,
      successCount: response.successCount,
      failureCount: response.failureCount,
      totalDevices: tokens.length,
      removedInvalidTokens: invalidTokens.length,
    });
  } catch (err) {
    console.error("❌ send_notification error:", err);
    return reply(500, {
      success: false,
      error: "Server error while sending notifications ❌",
    });
  }
};