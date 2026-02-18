const crypto = require("crypto");
const { Pool } = require("pg");
const bcrypt = require("bcryptjs");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS"
};

exports.handler = async function (event) {

  // ✅ PREFLIGHT
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  // ✅ STATIC QR ENTRY (GET) — CREATE TOKEN + TEMP ROW + REDIRECT
  if (event.httpMethod === "GET") {
    try {
      const token = crypto.randomBytes(24).toString("hex");
      const expires = new Date(Date.now() + 60 * 60 * 1000); // 1 hour

      const client = await pool.connect();

      // IMPORTANT: email is NOT NULL in your table
      const tempEmail = `pending_${token}@temp.local`;
      const tempPhone = "0000000000";

      await client.query(
        `INSERT INTO rsms
         (role, email, phone, active, onboard_token, onboard_token_expires)
         VALUES ('rsm', $1, $2, false, $3, $4)`,
        [tempEmail, tempPhone, token, expires]
      );

      client.release();

      return {
        statusCode: 302,
        headers: {
          Location: `${SITE}/rsm-onboard.html?token=${token}`
        }
      };

    } catch (err) {
      console.error("rsm-onboard GET error:", err);
      return { statusCode: 500, body: "Server error" };
    }
  }

  // ✅ COMPLETE ONBOARD (POST)
  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers: corsHeaders,
      body: "Method Not Allowed"
    };
  }

  try {
    const { token, password, name, region } = JSON.parse(event.body || "{}");

    if (!token || !password || !name || !region) {
      return { statusCode: 400, headers: corsHeaders, body: "Missing required fields" };
    }

    if (password.length < 8) {
      return { statusCode: 400, headers: corsHeaders, body: "Password must be at least 8 characters" };
    }

    const client = await pool.connect();

    const result = await client.query(
      `SELECT id, onboard_token_expires
       FROM rsms
       WHERE onboard_token = $1
       AND role = 'rsm'
       LIMIT 1`,
      [token]
    );

    if (result.rows.length === 0) {
      client.release();
      return { statusCode: 400, headers: corsHeaders, body: "Invalid link" };
    }

    const rsm = result.rows[0];

    if (!rsm.onboard_token_expires || new Date(rsm.onboard_token_expires) < new Date()) {
      client.release();
      return { statusCode: 400, headers: corsHeaders, body: "Link expired" };
    }

    const hashedPassword = await bcrypt.hash(password, 12);

    await client.query(
      `UPDATE rsms
       SET password_hash = $1,
           name = $2,
           region = $3,
           active = true,
           onboard_token = NULL,
           onboard_token_expires = NULL
       WHERE id = $4`,
      [hashedPassword, name, region, rsm.id]
    );

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ success: true })
    };

  } catch (err) {
    console.error("rsm-onboard POST error:", err);
    return { statusCode: 500, headers: corsHeaders, body: "Server error" };
  }
};
