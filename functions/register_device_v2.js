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

    const { email, deviceToken, platform } = body;

    if (!email || !deviceToken) {
      return reply(400, {
        success: false,
        error: "Missing email or deviceToken",
      });
    }

    console.log("📲 Device registration attempt:", {
      email,
      token: deviceToken.slice(0, 10) + "...",
    });

    const userRes = await db.query(
      `SELECT id, agent_id FROM users WHERE LOWER(email)=LOWER($1) LIMIT 1`,
      [email.trim()]
    );

    if (!userRes.rows.length) {
      return reply(404, { success: false, error: "User not found" });
    }

    const { id: userId, agent_id: agentId } = userRes.rows[0];

    if (!agentId) {
      console.log("⛔ No agent — device not registered");
      return reply(200, { success: true, message: "No agent attached" });
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
            agent_id=$2,
            platform=$3,
            updated_at=NOW()
        WHERE user_id=$4
        RETURNING *;
        `,
        [deviceToken, agentId, platform || "android", userId]
      );

      console.log("♻️ Device updated:", updated.rows[0]);
      return reply(200, { success: true, device: updated.rows[0] });
    }

    const inserted = await db.query(
      `
      INSERT INTO user_devices
        (user_id, agent_id, device_token, platform, created_at, updated_at)
      VALUES ($1,$2,$3,$4,NOW(),NOW())
      RETURNING *;
      `,
      [userId, agentId, deviceToken, platform || "android"]
    );

    console.log("✅ Device registered:", inserted.rows[0]);
    return reply(200, { success: true, device: inserted.rows[0] });

  } catch (err) {
    console.error("❌ register_device_v2 error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
