// @ts-nocheck

const crypto = require("crypto");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

function now() {
  return new Date();
}

function addHours(d, hrs) {
  return new Date(d.getTime() + hrs * 60 * 60 * 1000);
}

exports.handler = async function (event) {
  try {
    if (event.httpMethod !== "POST") {
      return { statusCode: 405, body: "Method Not Allowed" };
    }

    const { email, code } = JSON.parse(event.body || "{}");
    if (!email || !code) return { statusCode: 400, body: "Missing verification data" };

    const client = await pool.connect();

    const r = await client.query(
      "SELECT * FROM rsms WHERE email = $1 AND role = 'admin' AND active = true LIMIT 1",
      [email]
    );

    if (r.rows.length === 0) {
      client.release();
      return { statusCode: 403, body: "Unauthorized" };
    }

    const admin = r.rows[0];
    const t = now();

    // SMS lockout
    if (admin.sms_fail_until && new Date(admin.sms_fail_until) > t) {
      client.release();
      return { statusCode: 429, body: "Locked. Try again later." };
    }

    const expiresOk = admin.sms_expires && new Date(admin.sms_expires) > t;
    const codeOk = admin.sms_code && admin.sms_code === String(code).trim();

    if (!expiresOk || !codeOk) {
      const nextCount = (admin.sms_fail_count || 0) + 1;
      let failUntil = null;
      let resetCount = nextCount;

      // lock after 5 bad codes for 30 minutes
      if (nextCount >= 5) {
        failUntil = new Date(t.getTime() + 30 * 60 * 1000);
        resetCount = 0;
      }

      await client.query(
        "UPDATE rsms SET sms_fail_count = $1, sms_fail_until = $2 WHERE id = $3",
        [resetCount, failUntil, admin.id]
      );

      client.release();
      return { statusCode: 403, body: "Invalid or expired code" };
    }

    // success: clear codes and create session token
    const token = crypto.randomBytes(24).toString("hex"); // 48 chars
    const sessionExp = addHours(t, 8);

    const ip =
      (event.headers["x-forwarded-for"] || "").split(",")[0].trim() ||
      event.headers["client-ip"] ||
      "";

    await client.query(
      `UPDATE rsms
       SET sms_code = NULL,
           sms_expires = NULL,
           sms_fail_count = 0,
           sms_fail_until = NULL,
           admin_session_token = $1,
           admin_session_expires = $2,
           last_login_at = $3,
           last_login_ip = $4
       WHERE id = $5`,
      [token, sessionExp, t, ip, admin.id]
    );

    client.release();

    return {
      statusCode: 200,
      body: JSON.stringify({ success: true, token, expiresAt: sessionExp.toISOString() })
    };

  } catch (err) {
    console.error("admin-verify error:", err);
    return { statusCode: 500, body: JSON.stringify({ error: "Server error" }) };
  }
};
