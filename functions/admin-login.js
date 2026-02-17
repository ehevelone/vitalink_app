// @ts-nocheck

const bcrypt = require("bcryptjs");
const { Pool } = require("pg");
const twilio = require("twilio");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const twilioClient = twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN
);

function now() {
  return new Date();
}

function addMinutes(d, mins) {
  return new Date(d.getTime() + mins * 60 * 1000);
}

exports.handler = async function (event) {
  try {
    if (event.httpMethod !== "POST") {
      return { statusCode: 405, body: "Method Not Allowed" };
    }

    const { email, password } = JSON.parse(event.body || "{}");
    if (!email || !password) return { statusCode: 400, body: "Missing credentials" };

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

    // Password lockout
    if (admin.pw_fail_until && new Date(admin.pw_fail_until) > t) {
      client.release();
      return { statusCode: 429, body: "Locked. Try again later." };
    }

    const valid = await bcrypt.compare(password, admin.password_hash);

    if (!valid) {
      const nextCount = (admin.pw_fail_count || 0) + 1;
      let failUntil = null;
      let resetCount = nextCount;

      // lock after 5 bad attempts for 15 minutes
      if (nextCount >= 5) {
        failUntil = addMinutes(t, 15);
        resetCount = 0;
      }

      await client.query(
        "UPDATE rsms SET pw_fail_count = $1, pw_fail_until = $2 WHERE id = $3",
        [resetCount, failUntil, admin.id]
      );

      client.release();
      return { statusCode: 403, body: "Unauthorized" };
    }

    // Reset password fail counters on success
    await client.query(
      "UPDATE rsms SET pw_fail_count = 0, pw_fail_until = NULL WHERE id = $1",
      [admin.id]
    );

    // SMS cooldown: 60 seconds between sends
    if (admin.last_sms_sent_at && (t - new Date(admin.last_sms_sent_at)) < 60 * 1000) {
      client.release();
      return { statusCode: 429, body: "Please wait before requesting another code." };
    }

    if (!admin.phone) {
      client.release();
      return { statusCode: 400, body: "Admin phone not set" };
    }

    // Generate 6-digit code
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expires = addMinutes(t, 5);

    await client.query(
      "UPDATE rsms SET sms_code = $1, sms_expires = $2, last_sms_sent_at = $3 WHERE id = $4",
      [code, expires, t, admin.id]
    );

    client.release();

    await twilioClient.messages.create({
      body: `VitaLink Admin Code: ${code} (expires in 5 minutes)`,
      from: process.env.TWILIO_PHONE_NUMBER,
      to: admin.phone
    });

    return {
      statusCode: 200,
      body: JSON.stringify({ step: "verify_code" })
    };

  } catch (err) {
    console.error("admin-login error:", err);
    return { statusCode: 500, body: JSON.stringify({ error: "Server error" }) };
  }
};
