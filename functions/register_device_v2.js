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

exports.handler = async (event) => {
  console.log("🚀 register_device_v2 active");

  try {
    // ✅ CORS preflight
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    // ✅ Enforce POST
    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    // ✅ Safe body parsing
    let body = {};
    try {
      body = event.isBase64Encoded
        ? JSON.parse(Buffer.from(event.body, "base64").toString("utf8"))
        : JSON.parse(event.body || "{}");
    } catch (e) {
      console.error("❌ Body parse error:", e);
      return reply(400, {
        success: false,
        error: "Invalid request body",
      });
    }

    const { email, deviceToken, platform } = body;

    if (!email || !deviceToken) {
      return reply(400, {
        success: false,
        error: "Missing required fields (email, deviceToken)",
      });
    }

    console.log("📲 Device registration attempt:", {
      email,
      platform,
      token: deviceToken.slice(0, 10) + "...",
    });

    // ✅ Resolve USER
    const userRes = await db.query(
      `SELECT id FROM users WHERE LOWER(email) = LOWER($1) LIMIT 1`,
      [email.trim()]
    );

    if (!userRes.rows.length) {
      return reply(404, {
        success: false,
        error: "No user found with that email",
      });
    }

    const userId = userRes.rows[0].id;

    // 🔒 ENFORCE AGENT ASSOCIATION (REAL SCHEMA)
    const agentRes = await db.query(
      `
      SELECT agent_id
      FROM users
      WHERE id = $1
        AND agent_id IS NOT NULL
      LIMIT 1
      `,
      [userId]
    );

    if (!agentRes.rows.length) {
      console.log("⛔ Device NOT registered — user has no agent");
      return reply(200, {
        success: true,
        message: "User not associated with an agent — device not logged",
      });
    }

    const agentId = agentRes.rows[0].agent_id;
    console.log("✅ Agent confirmed:", agentId);

    // 🔁 Check for existing device token
    const existing = await db.query(
      `
      SELECT id
      FROM user_devices
      WHERE device_token = $1
      LIMIT 1
      `,
      [deviceToken]
    );

    if (existing.rows.length) {
      const updated = await db.query(
        `
        UPDATE user_devices
        SET user_id    = $1,
            agent_id   = $2,
            platform   = $3,
            updated_at = NOW()
        WHERE device_token = $4
        RETURNING id, user_id, agent_id, device_token, platform;
        `,
        [userId, agentId, platform || "android", deviceToken]
      );

      console.log("♻️ Device updated:", updated.rows[0]);

      return reply(200, {
        success: true,
        message: "Device updated ♻️",
        device: updated.rows[0],
      });
    }

    // ✅ Insert new device (agent-scoped)
    const inserted = await db.query(
      `
      INSERT INTO user_devices
        (user_id, agent_id, device_token, platform, created_at, updated_at)
      VALUES
        ($1, $2, $3, $4, NOW(), NOW())
      RETURNING id, user_id, agent_id, device_token, platform;
      `,
      [userId, agentId, deviceToken, platform || "android"]
    );

    console.log("✅ New device registered:", inserted.rows[0]);

    return reply(200, {
      success: true,
      message: "Device registered ✅",
      device: inserted.rows[0],
    });

  } catch (err) {
    console.error("❌ register_device_v2 error:", err);
    return reply(500, {
      success: false,
      error: "Server error while registering device ❌",
    });
  }
};
