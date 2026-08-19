const db = require("./services/db");
const { decrypt } = require("./encrypt");
const {
  clean,
  parseBody,
  reply,
  verifyUserSession,
} = require("./services/profile-share-sync");

function normalizeCode(value) {
  return String(value || "")
    .replace(/[\u2010-\u2015\u2212]/g, "-")
    .replace(/[^A-Za-z0-9-]/g, "")
    .trim()
    .toUpperCase();
}

async function cleanupExpiredTransfers() {
  await db.query(`
    DELETE FROM device_transfer_packages
    WHERE expires_at < NOW()
       OR status = 'redeemed'
  `);
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

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureSchema();
    await cleanupExpiredTransfers();

    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    const sessionToken = clean(body.sessionToken);
    const transferCode = normalizeCode(body.transferCode || body.transfer_code);

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    if (!transferCode) {
      return reply(400, {
        success: false,
        error: "Enter a transfer code",
      });
    }

    const transfer = await db.query(
      `
      SELECT id, encrypted_payload
      FROM device_transfer_packages
      WHERE transfer_code = $1
        AND user_id = $2
        AND status = 'pending'
        AND expires_at > NOW()
      LIMIT 1
      `,
      [transferCode, userId]
    );

    if (!transfer.rows.length) {
      return reply(404, {
        success: false,
        error: "Transfer code not found or expired",
      });
    }

    const decrypted = JSON.parse(decrypt(transfer.rows[0].encrypted_payload));

    await db.query(
      `
      UPDATE device_transfer_packages
      SET status = 'redeemed',
          redeemed_at = NOW()
      WHERE id = $1
      `,
      [transfer.rows[0].id]
    );

    await cleanupExpiredTransfers();

    return reply(200, {
      success: true,
      payload: decrypted.payload,
    });
  } catch (err) {
    console.error("redeem_device_transfer error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
