// functions/check_user.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(success, obj = {}, code = 200) {
  return {
    statusCode: code,
    headers,
    body: JSON.stringify({ success, ...obj }),
  };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return { statusCode: 200, headers, body: "" };
    }

    if (event.httpMethod !== "POST") {
      return reply(false, { error: "Method Not Allowed" }, 405);
    }

    const { email, password, device_id, replace } =
      JSON.parse(event.body || "{}");

    if (!email || !password) {
      return reply(false, { error: "Email and password required" }, 400);
    }

    // 🔎 Get user
    const result = await db.query(
      `SELECT id, email, password_hash, first_name, last_name, agent_id
       FROM users
       WHERE LOWER(email) = LOWER($1)
       LIMIT 1`,
      [email.trim()]
    );

    if (!result.rows.length) {
      return reply(false, { error: "User not found" }, 404);
    }

    const user = result.rows[0];
    const valid = await bcrypt.compare(password, user.password_hash);

    if (!valid) {
      return reply(false, { error: "Invalid password" }, 401);
    }

    // 🔥 DEVICE ENFORCEMENT (using user_devices table)
    if (device_id) {
      const deviceResult = await db.query(
        `SELECT device_id FROM user_devices WHERE user_id = $1 LIMIT 1`,
        [user.id]
      );

      // No device registered yet → insert
      if (!deviceResult.rows.length) {
        await db.query(
          `INSERT INTO user_devices (user_id, device_id)
           VALUES ($1, $2)`,
          [user.id, device_id]
        );
      } else {
        const existingDevice = deviceResult.rows[0].device_id;

        if (existingDevice !== device_id) {
          if (replace === true) {
            await db.query(
              `UPDATE user_devices
               SET device_id = $1, updated_at = NOW()
               WHERE user_id = $2`,
              [device_id, user.id]
            );
          } else {
            return reply(false, { error: "DEVICE_ACTIVE" }, 403);
          }
        }
      }
    }

    return reply(true, {
      user: {
        id: user.id,
        email: user.email,
        firstName: user.first_name,
        lastName: user.last_name,
        agent_id: user.agent_id,
      },
    });
  } catch (err) {
    console.error("❌ check_user error:", err);
    return reply(false, { error: "Server error" }, 500);
  }
};