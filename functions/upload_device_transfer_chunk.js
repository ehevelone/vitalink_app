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
    const chunkData = clean(body.chunkData);
    if (!(await verifyUserSession(userId, clean(body.sessionToken)))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    if (!(await verifyActiveUserDevice(userId, deviceId))) {
      return reply(403, { success: false, error: "Device is not active" });
    }
    if (!transferId || !Number.isInteger(chunkIndex) || chunkIndex < 0 ||
        !chunkData || chunkData.length > 2 * 1024 * 1024) {
      return reply(400, { success: false, error: "Invalid transfer chunk" });
    }
    const owner = await db.query(
      `SELECT chunk_count FROM device_transfer_packages
       WHERE id=$1 AND user_id=$2 AND status='pending' AND expires_at>NOW()`,
      [transferId, userId]
    );
    if (!owner.rows.length || chunkIndex >= owner.rows[0].chunk_count) {
      return reply(404, { success: false, error: "Transfer not found" });
    }
    await db.query(
      `INSERT INTO device_transfer_chunks (transfer_id, chunk_index, chunk_data)
       VALUES ($1,$2,$3)
       ON CONFLICT (transfer_id, chunk_index)
       DO UPDATE SET chunk_data=EXCLUDED.chunk_data`,
      [transferId, chunkIndex, chunkData]
    );
    return reply(200, { success: true });
  } catch (err) {
    console.error("upload_device_transfer_chunk error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
