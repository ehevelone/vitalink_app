// @ts-nocheck

const crypto = require("crypto");
const { Pool } = require("pg");
const { hashPassword, verifyPassword } = require("./services/passwords");

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

    const email = (parsed.email || "").trim().toLowerCase();
    const password = parsed.password || "";

    if (!email || !password) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Missing credentials" })
      };
    }

    client = await pool.connect();

    const result = await client.query(
      `
      SELECT id, email, password_hash, phone, role, active
      FROM rsms
      WHERE LOWER(email) = LOWER($1)
        AND role IN ('admin', 'rsm')
      LIMIT 1
      `,
      [email]
    );

    if (result.rows.length === 0) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Invalid credentials" })
      };
    }

    const user = result.rows[0];

    if (user.role === "admin" && user.active !== true) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Account inactive or setup incomplete" })
      };
    }

    if (!user.password_hash || user.password_hash === "PENDING_SETUP") {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Account setup incomplete" })
      };
    }

    const passwordCheck = await verifyPassword(password, user.password_hash);
    const valid = passwordCheck.valid;

    if (!valid) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Invalid credentials" })
      };
    }

    if (passwordCheck.legacy) {
      await client.query(
        "UPDATE rsms SET password_hash = $1 WHERE id = $2",
        [await hashPassword(password), user.id]
      );
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
