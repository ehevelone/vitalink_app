// functions/create-rsm.js
const { requireAdmin } = require("./_adminAuth");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
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

  // 🔐 Admin check
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

    // Prevent duplicates
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

    await client.query(
      "INSERT INTO rsms (role, email, phone, active) VALUES ('rsm', $1, $2, true)",
      [email, phone]
    );

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ success: true })
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
