// functions/update_user_profile.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");
const { verifyUserSession } = require("./services/user-auth");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    let body = {};
    try {
      body = JSON.parse(event.body || "{}");
    } catch (e) {
      return reply(400, {
        success: false,
        error: "Invalid request body",
      });
    }

    const {
      currentEmail,
      email,
      name,
      phone,
      password,
      userId,
      sessionToken,
    } = body;

    if (!currentEmail || !userId) {
      return reply(400, {
        success: false,
        error: "currentEmail and userId are required",
      });
    }

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const owner = await db.query(
      `SELECT id FROM users WHERE id = $1 AND LOWER(email) = LOWER($2) LIMIT 1`,
      [userId, currentEmail.trim()]
    );
    if (!owner.rows.length) {
      return reply(403, { success: false, error: "Account does not match the active session" });
    }

    const updates = [];
    const values = [];
    let idx = 1;

    // ✅ Split full name into first + last
    if (name) {
      const parts = name.trim().split(" ");
      const firstName = parts.shift();
      const lastName = parts.join(" ") || "";

      updates.push(`first_name = $${idx++}`);
      values.push(firstName);

      updates.push(`last_name = $${idx++}`);
      values.push(lastName);
    }

    if (email) {
      const normalizedEmail = email.trim().toLowerCase();
      const duplicate = await db.query(
        `SELECT id FROM users WHERE LOWER(email) = $1 AND id <> $2 LIMIT 1`,
        [normalizedEmail, userId]
      );
      if (duplicate.rows.length) {
        return reply(409, { success: false, error: "That email address is already in use" });
      }
      updates.push(`email = $${idx++}`);
      values.push(normalizedEmail);
    }

    if (phone) {
      updates.push(`phone = $${idx++}`);
      values.push(phone);
    }

    if (password) {
      const hashed = await bcrypt.hash(password, 10);
      updates.push(`password_hash = $${idx++}`);
      values.push(hashed);
    }

    if (!updates.length) {
      return reply(400, {
        success: false,
        error: "No fields provided to update",
      });
    }

    values.push(userId);

    const query = `
      UPDATE users
      SET ${updates.join(", ")}
      WHERE id = $${idx}
      RETURNING id, email, first_name, last_name, phone;
    `;

    const result = await db.query(query, values);

    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: "User not found",
      });
    }

    return reply(200, {
      success: true,
      message: "User profile updated ✅",
      user: result.rows[0],
    });

  } catch (err) {
    console.error("❌ update_user_profile error:", err.message);
    return reply(500, {
      success: false,
      error: "Server error while updating user ❌",
    });
  }
};
