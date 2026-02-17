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

exports.handler = async function (event) {
  try {
    if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        body: "Method Not Allowed"
      };
    }

    const { email, password } = JSON.parse(event.body || "{}");

    if (!email || !password) {
      return {
        statusCode: 400,
        body: "Missing credentials"
      };
    }

    const client = await pool.connect();

    const result = await client.query(
      "SELECT * FROM rsms WHERE email = $1 AND role = 'admin' AND active = true",
      [email]
    );

    if (result.rows.length === 0) {
      client.release();
      return {
        statusCode: 403,
        body: "Unauthorized"
      };
    }

    const admin = result.rows[0];

    const validPassword = await bcrypt.compare(
      password,
      admin.password_hash
    );

    if (!validPassword) {
      client.release();
      return {
        statusCode: 403,
        body: "Unauthorized"
      };
    }

    // Generate 6-digit code
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expires = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes

    await client.query(
      "UPDATE rsms SET sms_code = $1, sms_expires = $2 WHERE id = $3",
      [code, expires, admin.id]
    );

    client.release();

    // Send SMS
    await twilioClient.messages.create({
      body: `Your VitaLink admin login code is: ${code}`,
      from: process.env.TWILIO_PHONE_NUMBER,
      to: admin.phone
    });

    return {
      statusCode: 200,
      body: JSON.stringify({ step: "verify_code" })
    };

  } catch (err) {
    console.error("Admin login error:", err);

    return {
      statusCode: 500,
      body: JSON.stringify({ error: "Server error" })
    };
  }
};
