// functions/update_user_profile.js
//
// Updates the account holder's phone number. The account name and email are
// locked after registration and change only through account_correction
// (password plus an emailed code); the password changes only through the
// reset flow. Any name, email, or password sent here is ignored, so a modified
// app cannot change them.
const db = require("./services/db");
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

    const { currentEmail, phone, userId, sessionToken } = body;

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

    if (!phone) {
      // Nothing changeable was sent; report the account as it is.
      const current = await db.query(
        `SELECT id, email, first_name, last_name, phone FROM users WHERE id = $1 LIMIT 1`,
        [userId]
      );
      return reply(200, {
        success: true,
        message: "Nothing to update",
        user: current.rows[0] || null,
      });
    }

    const result = await db.query(
      `
      UPDATE users
      SET phone = $1
      WHERE id = $2
      RETURNING id, email, first_name, last_name, phone;
      `,
      [phone, userId]
    );

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
