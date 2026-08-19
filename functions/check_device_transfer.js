const db = require("./services/db");
const {
  clean,
  parseBody,
  reply,
  verifyUserSession,
} = require("./services/profile-share-sync");

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

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const transfer = await db.query(
      `
      SELECT transfer_code, expires_at
      FROM device_transfer_packages
      WHERE user_id = $1
        AND status = 'pending'
        AND expires_at > NOW()
      ORDER BY created_at DESC
      LIMIT 1
      `,
      [userId]
    );

    if (!transfer.rows.length) {
      return reply(200, {
        success: true,
        hasTransfer: false,
      });
    }

    return reply(200, {
      success: true,
      hasTransfer: true,
      transferCode: transfer.rows[0].transfer_code,
      expiresAt: transfer.rows[0].expires_at,
    });
  } catch (err) {
    console.error("check_device_transfer error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
