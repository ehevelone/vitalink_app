// functions/create-rsm.js
const crypto = require("crypto");
const { requireAdmin } = require("./_adminAuth");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";
const FUNCTION_URL = "https://vitalink-app.netlify.app/.netlify/functions/rsm-onboard";

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type, x-admin-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers: corsHeaders, body: "Method Not Allowed" };
  }

  const auth = await requireAdmin(event);
  if (auth.error) {
    return { statusCode: 401, headers: corsHeaders, body: auth.error };
  }

  try {
    const { email, phone } = JSON.parse(event.body || "{}");

    if (!email || !phone) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Missing email or phone"
      };
    }

    const client = await pool.connect();

    const existing = await client.query(
      "SELECT id FROM rsms WHERE email=$1 LIMIT 1",
      [email]
    );

    if (existing.rows.length > 0) {
      client.release();
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "RSM already exists"
      };
    }

    const token = crypto.randomBytes(24).toString("hex");
    const expires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    // Required because password_hash is NOT NULL
    const tempPasswordHash = "PENDING_SETUP";

    await client.query(
      `INSERT INTO rsms 
        (role, email, password_hash, name, region, phone, active, created_at, onboard_token, onboard_token_expires) 
       VALUES ('rsm', $1, $2, $3, $4, $5, false, NOW(), $6, $7)`,
      [
        email,
        tempPasswordHash,
        "",        // name placeholder
        "",        // region placeholder
        phone,
        token,
        expires
      ]
    );

    client.release();

    const onboardingUrl = `${FUNCTION_URL}?token=${token}`;

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        success: true,
        onboard_url: onboardingUrl,
        onboard_token: token
      })
    };

  } catch (err) {
    console.error("create-rsm error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };
  }
};
