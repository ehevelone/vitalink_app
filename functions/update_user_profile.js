// functions/update_user_profile.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");

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
    } = body;

    if (!currentEmail) {
      return reply(400, {
        success: false,
        error: "currentEmail is required",
      });
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
      updates.push(`email = $${idx++}`);
      values.push(email);
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

    values.push(currentEmail.trim());

    const query = `
      UPDATE users
      SET ${updates.join(", ")}
      WHERE LOWER(email) = LOWER($${idx})
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
