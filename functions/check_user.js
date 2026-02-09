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
    // ✅ CORS preflight
    if (event.httpMethod === "OPTIONS") {
      return { statusCode: 200, headers, body: "" };
    }

    if (event.httpMethod !== "POST") {
      return reply(false, { error: "Method Not Allowed" }, 405);
    }

    const { email, password } = JSON.parse(event.body || "{}");

    if (!email || !password) {
      return reply(false, { error: "Email and password required" }, 400);
    }

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
