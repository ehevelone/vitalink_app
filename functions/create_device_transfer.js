const crypto = require("crypto");
const db = require("./services/db");
const { encrypt } = require("./encrypt");
const {
  clean,
  parseBody,
  reply,
  verifyUserSession,
} = require("./services/profile-share-sync");

const MAX_BODY_BYTES = 8 * 1024 * 1024;
const TRANSFER_WINDOW = "6 hours";

function createTransferCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 8; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return `MOVE-${code}`;
}

async function ensureSchema() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS device_transfer_packages (
      id UUID PRIMARY KEY,
      user_id TEXT NOT NULL,
      transfer_code TEXT UNIQUE NOT NULL,
      encrypted_payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '6 hours',
      redeemed_at TIMESTAMPTZ
    )
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_device_transfer_code
    ON device_transfer_packages (transfer_code)
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_device_transfer_expires
    ON device_transfer_packages (expires_at)
  `);
}

async function cleanupExpiredTransfers() {
  await db.query(`
    DELETE FROM device_transfer_packages
    WHERE expires_at < NOW()
       OR status = 'redeemed'
  `);
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    const bodyBytes = Buffer.byteLength(event.body || "", "utf8");
    if (bodyBytes > MAX_BODY_BYTES) {
      return reply(413, {
        success: false,
        error: "Transfer is too large. Remove unused card images and try again.",
      });
    }

    await ensureSchema();
    await cleanupExpiredTransfers();

    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    const sessionToken = clean(body.sessionToken);
    const payload = body.payload;

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    if (!payload || typeof payload !== "object") {
      return reply(400, {
        success: false,
        error: "Missing transfer payload",
      });
    }

    let transferCode = createTransferCode();
    for (let i = 0; i < 8; i++) {
      const existing = await db.query(
        "SELECT id FROM device_transfer_packages WHERE transfer_code = $1",
        [transferCode]
      );
      if (!existing.rows.length) break;
      transferCode = createTransferCode();
    }

    const packageId = crypto.randomUUID();
    const encryptedPayload = encrypt(JSON.stringify({
      payload,
      createdAt: new Date().toISOString(),
      expiresIn: TRANSFER_WINDOW,
    }));

    await db.query(
      `
      INSERT INTO device_transfer_packages (
        id,
        user_id,
        transfer_code,
        encrypted_payload,
        expires_at
      )
      VALUES ($1,$2,$3,$4,NOW() + INTERVAL '6 hours')
      `,
      [packageId, userId, transferCode, encryptedPayload]
    );

    return reply(200, {
      success: true,
      transferCode,
      expiresInHours: 6,
    });
  } catch (err) {
    console.error("create_device_transfer error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
