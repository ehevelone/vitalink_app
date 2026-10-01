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
    const transferId = clean(body.transferId || body.transfer_id);
    if (!(await verifyUserSession(userId, clean(body.sessionToken)))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    if (!(await verifyActiveUserDevice(userId, deviceId))) {
      return reply(403, { success: false, error: "Device is not active" });
    }
    if (!transferId) return reply(400, { success: false, error: "Missing transfer" });
    const result = await db.query(
      `DELETE FROM device_transfer_packages
       WHERE id=$1 AND user_id=$2 AND status='downloaded'
         AND redeemed_device_id=$3 AND expires_at>NOW()
       RETURNING id`,
      [transferId, userId, deviceId]
    );
    if (!result.rows.length) {
      return reply(404, { success: false, error: "Transfer not found" });
    }
    return reply(200, { success: true });
  } catch (err) {
    console.error("complete_device_transfer error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
