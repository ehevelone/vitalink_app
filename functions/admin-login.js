// @ts-nocheck

const bcrypt = require("bcryptjs");
const crypto = require("crypto");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: corsHeaders(),
      body: ""
    };
  }

  let client;

  try {

    if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Method Not Allowed" })
      };
    }

    /* ✅ SAFE JSON PARSE (SURGICAL FIX) */
    let parsed;
    try {
      parsed = JSON.parse(event.body || "{}");
    } catch (e) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Invalid JSON" })
      };
    }

    const { email, password } = parsed;

    if (!email || !password) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Missing credentials" })
      };
    }

    client = await pool.connect();

    const result = await client.query(
      "SELECT id, password_hash, phone, role FROM rsms WHERE email = $1 AND active = true LIMIT 1",
      [email]
    );

    if (result.rows.length === 0) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Unauthorized" })
      };
    }

    const user = result.rows[0];

    const valid = await bcrypt.compare(password, user.password_hash);

    if (!valid) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Unauthorized" })
      };
    }

    // ==========================
    // ADMIN FLOW (2FA)
    // ==========================
    if (user.role === "admin") {

      if (!user.phone) {
        client.release();
        return {
          statusCode: 400,
          headers: corsHeaders(),
          body: JSON.stringify({ success:false, error:"Admin phone not configured" })
        };
      }

      client.release();

      return {
        statusCode: 200,
        headers: corsHeaders(),
        body: JSON.stringify({
          step: "firebase_2fa",
          phone: user.phone,
          role: "admin"
        })
      };
    }

    // ==========================
    // RSM FLOW (SESSION)
    // ==========================
    if (user.role === "rsm") {

      const sessionToken = crypto.randomBytes(32).toString("hex");
      const expires = new Date(Date.now() + 8 * 60 * 60 * 1000);

      await client.query(
        `UPDATE rsms
         SET admin_session_token = $1,
             admin_session_expires = $2
         WHERE id = $3`,
        [sessionToken, expires, user.id]
      );

      client.release();

      return {
        statusCode: 200,
        headers: corsHeaders(),
        body: JSON.stringify({
          step: "login_success",
          role: "rsm",
          token: sessionToken
        })
      };
    }

    client.release();

    return {
      statusCode: 403,
      headers: corsHeaders(),
      body: JSON.stringify({ success:false, error:"Unauthorized" })
    };

  } catch (err) {
    console.error("admin-login error:", err);

    if (client) client.release(); // ✅ SAFETY FIX

    return {
      statusCode: 500,
      headers: corsHeaders(),
      body: JSON.stringify({ success:false, error:"Server error" })
    };
  }
};

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };
}