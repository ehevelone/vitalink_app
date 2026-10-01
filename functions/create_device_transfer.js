const crypto = require("crypto");
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
    const chunkCount = Number(body.chunkCount);
    if (!(await verifyUserSession(userId, clean(body.sessionToken)))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    if (!(await verifyActiveUserDevice(userId, deviceId))) {
      return reply(403, { success: false, error: "Device is not active" });
    }
    if (!Number.isInteger(chunkCount) || chunkCount < 1 || chunkCount > 100) {
      return reply(400, { success: false, error: "Invalid transfer package" });
    }

    await db.query(
      `DELETE FROM device_transfer_packages
       WHERE user_id=$1 AND status IN ('pending','downloaded')`,
      [userId]
    );
    const transferCode = `VT-${crypto.randomBytes(16).toString("hex").toUpperCase()}`;
    const transferId = crypto.randomUUID();
    const transfer = await db.query(
      `INSERT INTO device_transfer_packages
        (id, user_id, transfer_code, chunk_count)
       VALUES ($1,$2,$3,$4)
       RETURNING id`,
      [transferId, userId, transferCode, chunkCount]
    );
    return reply(200, {
      success: true,
      transferId: transfer.rows[0].id,
      transferCode,
      expiresInHours: 6,
    });
  } catch (err) {
    console.error("create_device_transfer error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
