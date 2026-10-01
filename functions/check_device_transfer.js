const { verifyUserSession } = require("./services/user-auth");
const {
  clean,
  db,
  ensureSchema,
  parseBody,
  reply,
  verifyActiveUserDevice,
} = require("./services/device-transfer");

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    await ensureSchema();
    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    const deviceId = clean(body.deviceId || body.device_id);
    if (!(await verifyUserSession(userId, clean(body.sessionToken)))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    if (!(await verifyActiveUserDevice(userId, deviceId))) {
      return reply(403, { success: false, error: "Device is not active" });
    }
    const result = await db.query(
      `SELECT created_at, expires_at FROM device_transfer_packages
       WHERE user_id=$1 AND status IN ('pending','downloaded') AND expires_at>NOW()
       ORDER BY created_at DESC LIMIT 1`,
      [userId]
    );
    return reply(200, {
      success: true,
      pending: result.rows.length > 0,
      transfer: result.rows[0] || null,
    });
  } catch (err) {
    console.error("check_device_transfer error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
