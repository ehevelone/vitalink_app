// functions/mark_reviewed.js
const db = require("./services/db");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(statusCode, obj) {
  return {
    statusCode,
    headers,
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, { ok: true });

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

    const email = String(body.email || "").trim().toLowerCase();
    if (!email) {
      return reply(400, { success: false, error: "Missing email" });
    }

    // ✅ Find user
    const userRes = await db.query(
      `SELECT id FROM users WHERE LOWER(email) = LOWER($1) LIMIT 1`,
      [email]
    );

    if (!userRes.rows.length) {
      return reply(404, { success: false, error: "User not found" });
    }

    const userId = userRes.rows[0].id;

    // ✅ Mark responded this cycle
    // IMPORTANT: This is the flag send_notification uses to STOP re-notifying.
    const updated = await db.query(
      `
      UPDATE users
      SET last_reviewed = NOW(),
          updated_at = NOW()
      WHERE id = $1
      RETURNING id, email, last_reviewed;
      `,
      [userId]
    );

    return reply(200, {
      success: true,
      user: updated.rows[0],
    });
  } catch (err) {
    console.error("❌ mark_reviewed error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};