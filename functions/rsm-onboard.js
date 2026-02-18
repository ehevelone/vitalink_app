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

  // PREFLIGHT
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  // ==========================
  // 🔹 QR HIT (GET)
  // ==========================
  if (event.httpMethod === "GET") {
    return {
      statusCode: 302,
      headers: {
        Location: `${SITE}/rsm-onboard.html`
      }
    };
  }

  // ==========================
  // 🔹 COMPLETE REGISTRATION
  // ==========================
  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers: corsHeaders,
      body: "Method Not Allowed"
    };
  }

  try {
    const { email, password, name, region, phone } = JSON.parse(event.body || "{}");

    if (!email || !password || !name || !region || !phone) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Missing required fields"
      };
    }

    if (password.length < 8) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Password must be at least 8 characters"
      };
    }

    const client = await pool.connect();

    // Prevent duplicate
    const existing = await client.query(
      "SELECT id FROM rsms WHERE email=$1 LIMIT 1",
      [email]
    );

    if (existing.rows.length > 0) {
      client.release();
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Email already registered"
      };
    }

    const hashedPassword = await bcrypt.hash(password, 12);

    await client.query(
      `INSERT INTO rsms
       (role, email, password_hash, name, region, phone, active, created_at)
       VALUES ('rsm', $1, $2, $3, $4, $5, true, NOW())`,
      [email, hashedPassword, name, region, phone]
    );

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ success: true })
    };

  } catch (err) {
    console.error("rsm-onboard POST error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };
  }
};
