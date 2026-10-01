const { verifyUserSession } = require("./services/user-auth");
const {
  clean,
  db,
  ensureSchema,
  normalizeCode,
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
    const transferCode = normalizeCode(body.transferCode || body.transfer_code);
    if (!(await verifyUserSession(userId, clean(body.sessionToken)))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    if (!(await verifyActiveUserDevice(userId, deviceId))) {
      return reply(403, { success: false, error: "Device is not active" });
    }
    if (!transferCode) return reply(400, { success: false, error: "Enter a transfer code" });

    const result = await db.query(
      `UPDATE device_transfer_packages
       SET status='downloaded', downloaded_at=COALESCE(downloaded_at,NOW()),
           redeemed_device_id=COALESCE(redeemed_device_id,$3)
       WHERE user_id=$1 AND transfer_code=$2
         AND (
           (status='pending' AND redeemed_device_id IS NULL)
           OR (status='downloaded' AND redeemed_device_id=$3)
         )
         AND expires_at>NOW()
         AND chunk_count > 0
         AND chunk_count = (
           SELECT COUNT(*)::INTEGER
           FROM device_transfer_chunks
           WHERE transfer_id=device_transfer_packages.id
         )
       RETURNING id, chunk_count, expires_at`,
      [userId, transferCode, deviceId]
    );
    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: "That transfer code is invalid, expired, or is still being prepared",
      });
    }
    return reply(200, {
      success: true,
      transferId: result.rows[0].id,
      chunkCount: result.rows[0].chunk_count,
      expiresAt: result.rows[0].expires_at,
    });
  } catch (err) {
    console.error("redeem_device_transfer error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
