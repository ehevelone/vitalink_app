const db = require("./services/db");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

async function ensureDeviceDeliveryColumns() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS user_devices (
      id SERIAL PRIMARY KEY,
      user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      agent_id INTEGER REFERENCES agents(id) ON DELETE CASCADE,
      device_id TEXT,
      device_token TEXT,
      platform TEXT,
      push_status TEXT,
      last_push_at TIMESTAMPTZ,
      last_push_success_at TIMESTAMPTZ,
      last_push_failure_at TIMESTAMPTZ,
      last_push_error TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);

  await db.query(`
    ALTER TABLE user_devices
    ADD COLUMN IF NOT EXISTS agent_id INTEGER REFERENCES agents(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS device_id TEXT,
    ADD COLUMN IF NOT EXISTS device_token TEXT,
    ADD COLUMN IF NOT EXISTS platform TEXT,
    ADD COLUMN IF NOT EXISTS push_status TEXT,
    ADD COLUMN IF NOT EXISTS last_push_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_push_success_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_push_failure_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_push_error TEXT,
    ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW()
  `);

  await db.query(`
    ALTER TABLE user_devices
    ALTER COLUMN user_id DROP NOT NULL
  `);

  await db.query(`
    ALTER TABLE user_devices
    ALTER COLUMN device_id DROP NOT NULL
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_user_devices_user_id
    ON user_devices(user_id)
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_user_devices_agent_id
    ON user_devices(agent_id)
  `);
}

async function verifyUserSession(userId, token) {
  if (!userId || !token) return false;

  await db.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ
  `);

  const result = await db.query(
    `
    SELECT id
    FROM users
    WHERE id = $1
      AND session_token = $2
      AND session_expires > NOW()
    LIMIT 1
    `,
    [userId, token]
  );

  return result.rows.length > 0;
}

exports.handler = async (event) => {
  console.log("🚀 register_device_v2 active");

  try {
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureDeviceDeliveryColumns();

    let body;
    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      return reply(400, { success: false, error: "Invalid JSON body" });
    }

    // 🔥 CHANGED: email → user_id
    const { user_id, deviceToken, fcmToken, platform, sessionToken } = body;
    const token = deviceToken || fcmToken;

    if (!user_id || !token) {
      return reply(400, {
        success: false,
        error: "Missing user_id or token",
      });
    }

    const authorized = await verifyUserSession(user_id, sessionToken);

    if (!authorized) {
      return reply(403, {
        success: false,
        error: "Unauthorized",
      });
    }

    console.log("📲 Device registration attempt:", {
      user_id,
      token: token.slice(0, 10) + "...",
      platform,
    });

    // 🔥 CHANGED: lookup by user_id instead of email
    const userRes = await db.query(
      `SELECT id, agent_id FROM users WHERE id = $1 LIMIT 1`,
      [user_id]
    );

    if (!userRes.rows.length) {
      return reply(404, { success: false, error: "User not found" });
    }

    const { id: userId, agent_id: agentId } = userRes.rows[0];

    const existingUserDevice = await db.query(
      `SELECT id FROM user_devices WHERE user_id = $1 LIMIT 1`,
      [userId]
    );

    if (existingUserDevice.rows.length) {
      await db.query(
        `
        UPDATE user_devices
        SET device_token=NULL,
            updated_at=NOW()
        WHERE device_token=$1
          AND id<>$2
        `,
        [token, existingUserDevice.rows[0].id]
      );

      const updated = await db.query(
        `
        UPDATE user_devices
        SET device_token=$1,
            platform=$2,
            agent_id=$3,
            push_status='registered',
            last_push_error=NULL,
            updated_at=NOW()
        WHERE id=$4
        RETURNING *;
        `,
        [token, platform || "unknown", agentId || null, existingUserDevice.rows[0].id]
      );

      console.log("Device updated for user:", updated.rows[0]?.id);
      return reply(200, { success: true, device: updated.rows[0] });
    }

    // 🔥 ALWAYS REGISTER DEVICE

    const existingToken = await db.query(
      `SELECT id FROM user_devices WHERE device_token = $1 LIMIT 1`,
      [token]
    );

    if (existingToken.rows.length) {
      const updated = await db.query(
        `
        UPDATE user_devices
        SET user_id=$1,
            agent_id=$2,
            platform=$3,
            push_status='registered',
            last_push_error=NULL,
            updated_at=NOW()
        WHERE id=$4
        RETURNING *;
        `,
        [userId, agentId || null, platform || "unknown", existingToken.rows[0].id]
      );

      console.log("Device token reused for user:", updated.rows[0]?.id);
      return reply(200, { success: true, device: updated.rows[0] });
    }

    const existing = await db.query(
      `SELECT id FROM user_devices WHERE user_id = $1 LIMIT 1`,
      [userId]
    );

    if (existing.rows.length) {
      const updated = await db.query(
        `
        UPDATE user_devices
        SET device_token=$1,
            platform=$2,
            agent_id=$3,
            push_status='registered',
            last_push_error=NULL,
            updated_at=NOW()
        WHERE user_id=$4
        RETURNING *;
        `,
        [token, platform || "unknown", agentId || null, userId]
      );

      console.log("♻️ Device updated:", updated.rows[0]);
      return reply(200, { success: true, device: updated.rows[0] });
    }

    const inserted = await db.query(
      `
      INSERT INTO user_devices
        (user_id, agent_id, device_token, platform, push_status, created_at, updated_at)
      VALUES ($1,$2,$3,$4,'registered',NOW(),NOW())
      RETURNING *;
      `,
      [userId, agentId || null, token, platform || "unknown"]
    );

    console.log("✅ Device inserted:", inserted.rows[0]);
    return reply(200, { success: true, device: inserted.rows[0] });

  } catch (err) {
    console.error("❌ register_device_v2 error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
