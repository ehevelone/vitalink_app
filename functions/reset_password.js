// functions/reset_password.js

const db = require("./services/db");
const bcrypt = require("bcryptjs");

const CORS_HEADERS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(statusCode, body) {
  return {
    statusCode,
    headers: CORS_HEADERS,
    body: JSON.stringify(body),
  };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return { statusCode: 200, headers: CORS_HEADERS, body: "" };
    }

    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    let body = {};
    try {
      body = event.isBase64Encoded
        ? JSON.parse(Buffer.from(event.body, "base64").toString("utf8"))
        : JSON.parse(event.body || "{}");
    } catch {
      return reply(400, { success: false, error: "Invalid request body" });
    }

    const { emailOrPhone, code, newPassword, role } = body;

    if (!emailOrPhone || !code || !newPassword || !role) {
      return reply(400, { success: false, error: "Missing required fields" });
    }

    if (role !== "users" && role !== "agents") {
      return reply(400, { success: false, error: "Invalid role" });
    }

    const email = emailOrPhone.trim().toLowerCase();

    const result = await db.query(
      `
      SELECT id, email, reset_code, reset_expires
      FROM ${role}
      WHERE LOWER(email) = $1
      LIMIT 1
      `,
      [email]
    );

    if (!result.rows.length) {
      return reply(404, { success: false, error: "No account found" });
    }

    const user = result.rows[0];

    // 🔐 Hardened reset code comparison
    const storedCode = String(user.reset_code ?? "").trim();
    const enteredCode = String(code ?? "").trim();

    if (storedCode.length === 0) {
      return reply(400, { success: false, error: "No reset code found" });
    }

    if (storedCode !== enteredCode) {
      return reply(400, { success: false, error: "Invalid reset code" });
    }

    if (!user.reset_expires || new Date(user.reset_expires) < new Date()) {
      return reply(400, { success: false, error: "Reset code expired" });
    }

    const hashed = await bcrypt.hash(newPassword, 12);

    const update = await db.query(
      `
      UPDATE ${role}
      SET password_hash = $1,
          reset_code = NULL,
          reset_expires = NULL
      WHERE id = $2
      RETURNING id
      `,
      [hashed, user.id]
    );

    if (update.rowCount === 0) {
      return reply(500, { success: false, error: "Password update failed" });
    }

    console.log(`✅ Password reset for ${user.email} (${role})`);

    return reply(200, { success: true });

  } catch (err) {
    console.error("❌ reset_password error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};