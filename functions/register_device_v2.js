const db = require("./services/db");
const { verifyUserSession } = require("./services/user-auth");
const { ensureDeviceSecuritySchema } = require("./services/device-security");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    await ensureDeviceSecuritySchema();

    const body = JSON.parse(event.body || "{}");
    const userId = body.user_id || body.userId;
    const fcmToken = body.deviceToken || body.fcmToken;
    const deviceId = body.device_id || body.deviceId;
    if (!userId || !fcmToken || !deviceId) {
      return reply(400, { success: false, error: "Missing user, device ID, or notification token" });
    }
    if (!(await verifyUserSession(userId, body.sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const user = await db.query("SELECT id, agent_id FROM users WHERE id=$1 LIMIT 1", [userId]);
    if (!user.rows.length) return reply(404, { success: false, error: "User not found" });

    const current = await db.query(
      "SELECT device_status FROM user_devices WHERE user_id=$1 AND device_id=$2 LIMIT 1",
      [userId, deviceId]
    );
    if (current.rows.length && current.rows[0].device_status !== "active") {
      return reply(403, { success: false, error: "DEVICE_REVOKED" });
    }

    await db.query(
      `UPDATE user_devices SET device_token=NULL, updated_at=NOW()
       WHERE device_token=$1 AND NOT (user_id=$2 AND device_id=$3)`,
      [fcmToken, userId, deviceId]
    );

    const result = await db.query(
      `INSERT INTO user_devices
        (user_id, agent_id, device_id, device_token, platform, push_status,
         device_status, last_seen_at, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,'registered','active',NOW(),NOW(),NOW())
       ON CONFLICT (user_id, device_id) WHERE user_id IS NOT NULL AND device_id IS NOT NULL
       DO UPDATE SET agent_id=EXCLUDED.agent_id, device_token=EXCLUDED.device_token,
         platform=EXCLUDED.platform, push_status='registered', last_push_error=NULL,
         last_seen_at=NOW(), updated_at=NOW()
       RETURNING id, user_id, device_id, platform, device_status, updated_at`,
      [userId, user.rows[0].agent_id || null, deviceId, fcmToken, body.platform || "unknown"]
    );

    return reply(200, { success: true, device: result.rows[0] });
  } catch (err) {
    console.error("register_device_v2 error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
