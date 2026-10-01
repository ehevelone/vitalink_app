const { verifyUserSession } = require("./services/user-auth");
const { clean, db, ensureSchema, parseBody, reply, verifyActiveUserDevice } = require("./services/device-transfer");

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    await ensureSchema();
    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    const deviceId = clean(body.deviceId || body.device_id);
    const transferId = clean(body.transferId || body.transfer_id);
    const chunkIndex = Number(body.chunkIndex);
    if (!(await verifyUserSession(userId, clean(body.sessionToken)))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    if (!(await verifyActiveUserDevice(userId, deviceId))) {
      return reply(403, { success: false, error: "Device is not active" });
    }
    if (!transferId || !Number.isInteger(chunkIndex) || chunkIndex < 0) {
      return reply(400, { success: false, error: "Invalid transfer chunk" });
    }
    const result = await db.query(
      `SELECT c.chunk_data
       FROM device_transfer_chunks c
       JOIN device_transfer_packages p ON p.id=c.transfer_id
       WHERE c.transfer_id=$1 AND c.chunk_index=$2 AND p.user_id=$3
         AND p.status='downloaded' AND p.redeemed_device_id=$4
         AND p.expires_at>NOW()
       LIMIT 1`,
      [transferId, chunkIndex, userId, deviceId]
    );
    if (!result.rows.length) {
      return reply(404, { success: false, error: "Transfer chunk not found" });
    }
    return reply(200, { success: true, chunkData: result.rows[0].chunk_data });
  } catch (err) {
    console.error("get_device_transfer_chunk error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
