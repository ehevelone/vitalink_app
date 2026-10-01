const db = require("./services/db");
const { ensureDeviceSecuritySchema } = require("./services/device-security");
const { verifyUserSession } = require("./services/user-auth");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    await ensureDeviceSecuritySchema();
    const body = JSON.parse(event.body || "{}");
    if (!body.userId || !body.deviceId) return reply(400, { success: false, error: "Missing device" });
    const existing = await db.query(
      `SELECT device_status, revocation_reason, revoked_at
       FROM user_devices
       WHERE user_id=$1 AND device_id=$2
       LIMIT 1`,
      [body.userId, body.deviceId]
    );
    if (existing.rows.length && existing.rows[0].device_status !== "active") {
      const revoked = existing.rows[0];
      return reply(200, {
        success: true,
        active: false,
        status: revoked.device_status,
        reason: revoked.revocation_reason,
        revokedAt: revoked.revoked_at,
      });
    }
    if (!(await verifyUserSession(body.userId, body.sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    if (!existing.rows.length) {
      return reply(200, { success: true, active: false, status: "unknown" });
    }
    await db.query(
      `UPDATE user_devices SET last_seen_at=NOW(), updated_at=NOW()
       WHERE user_id=$1 AND device_id=$2`,
      [body.userId, body.deviceId]
    );
    const row = existing.rows[0];
    return reply(200, {
      success: true,
      active: row.device_status === "active",
      status: row.device_status,
      reason: row.revocation_reason,
      revokedAt: row.revoked_at,
    });
  } catch (err) {
    console.error("check_device_status error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
