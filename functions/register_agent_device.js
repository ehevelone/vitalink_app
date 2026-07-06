const db = require("./services/db");
const { verifyAgentSession } = require("./services/agent-auth");

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

async function ensureAgentDeviceSupport() {
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
    ADD COLUMN IF NOT EXISTS agent_device_registered BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS agent_registered_at TIMESTAMPTZ,
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

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    let body;
    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      return reply(400, { success: false, error: "Invalid JSON body" });
    }

    const { agentId, agentSessionToken, deviceToken, fcmToken, platform } = body;
    const token = deviceToken || fcmToken;
    const numericAgentId = Number(agentId);

    if (!Number.isInteger(numericAgentId) || numericAgentId <= 0 || !token) {
      return reply(400, {
        success: false,
        error: "Missing agentId or token",
      });
    }

    const agent = await verifyAgentSession({
      agentId: numericAgentId,
      token: agentSessionToken,
    });

    if (!agent) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    await ensureAgentDeviceSupport();

    await db.query("BEGIN");

    try {
      await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`agent:${numericAgentId}`]);
      await db.query("SELECT pg_advisory_xact_lock(hashtext($1))", [`device:${token}`]);

      const tokenRow = await db.query(
        `
        SELECT id
        FROM user_devices
        WHERE device_token = $1
        LIMIT 1
        FOR UPDATE
        `,
        [token]
      );

      const agentRow = await db.query(
        `
        SELECT id
        FROM user_devices
        WHERE agent_id = $1
        LIMIT 1
        FOR UPDATE
        `,
        [numericAgentId]
      );

      const targetId = tokenRow.rows[0]?.id || agentRow.rows[0]?.id || null;

      if (targetId) {
        await db.query(
          `
          UPDATE user_devices
          SET device_token = NULL,
              updated_at = NOW()
          WHERE device_token = $1
            AND id <> $2
          `,
          [token, targetId]
        );

        await db.query(
          `
          UPDATE user_devices
          SET agent_id = NULL,
              updated_at = NOW()
          WHERE agent_id = $1
            AND id <> $2
          `,
          [numericAgentId, targetId]
        );

        const updated = await db.query(
          `
          UPDATE user_devices
          SET agent_id = $1,
              device_token = $2,
              platform = $3,
              push_status = 'registered',
              last_push_error = NULL,
              agent_device_registered = TRUE,
              agent_registered_at = NOW(),
              updated_at = NOW()
          WHERE id = $4
          RETURNING id, user_id, agent_id, platform, push_status, updated_at
          `,
          [numericAgentId, token, platform || "unknown", targetId]
        );

        await db.query("COMMIT");
        return reply(200, { success: true, device: updated.rows[0] });
      }

      const inserted = await db.query(
        `
        INSERT INTO user_devices
          (user_id, agent_id, device_token, platform, push_status, agent_device_registered, agent_registered_at, created_at, updated_at)
        VALUES (NULL, $1, $2, $3, 'registered', TRUE, NOW(), NOW(), NOW())
        RETURNING id, agent_id, platform, push_status, updated_at
        `,
        [numericAgentId, token, platform || "unknown"]
      );

      await db.query("COMMIT");
      return reply(200, { success: true, device: inserted.rows[0] });
    } catch (err) {
      await db.query("ROLLBACK");
      throw err;
    }
  } catch (err) {
    console.error("register_agent_device error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
