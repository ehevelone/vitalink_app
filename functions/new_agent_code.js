// functions/new_agent_code.js
const db = require("./services/db");
const { Pool } = require("pg");

const SITE = "https://myvitalink.app";

// ✅ CORS: allow the header your page actually sends (x-rsm-token)
const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type, Accept, x-admin-session, x-rsm-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400"
};

// ✅ Prefer a real Postgres connection string env var if you have one
const pool = new Pool({
  connectionString: process.env.SUPABASE_DB_URL || process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

function generateUnlockCode(prefix = "AG", length = 10) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return `${prefix}-${code}`;
}

exports.handler = async (event) => {
  try {
    // ✅ Handle CORS preflight
    if (event.httpMethod === "OPTIONS") {
      return { statusCode: 200, headers: corsHeaders, body: "" };
    }

    if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Method Not Allowed" })
      };
    }

    // ✅ Accept either header name (your UI uses x-rsm-token)
    const sessionToken =
      event.headers["x-rsm-token"] ||
      event.headers["x-admin-session"] ||
      event.headers["X-RSM-TOKEN"] ||
      event.headers["X-ADMIN-SESSION"];

    if (!sessionToken) {
      return {
        statusCode: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Missing session" })
      };
    }

    const client = await pool.connect();

    // ✅ Your current logic: rsms table stores admin_session_token/expiry
    const rsmResult = await client.query(
      `
      SELECT id
      FROM rsms
      WHERE admin_session_token = $1
        AND role = 'rsm'
        AND admin_session_expires > NOW()
      LIMIT 1
      `,
      [sessionToken]
    );

    client.release();

    if (rsmResult.rows.length === 0) {
      return {
        statusCode: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Invalid session" })
      };
    }

    const rsmId = rsmResult.rows[0].id;

    const unlockCode = generateUnlockCode();

    const agentResult = await db.query(
      `
      INSERT INTO agents (unlock_code, active, role, rsm_id, created_at)
      VALUES ($1, FALSE, 'agent', $2, NOW())
      RETURNING id
      `,
      [unlockCode, rsmId]
    );

    const agentId = agentResult.rows[0].id;

    return {
      statusCode: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ success: true, agentId, unlockCode })
    };
  } catch (err) {
    console.error("❌ new_agent_code error:", err);
    return {
      statusCode: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      body: JSON.stringify({ success: false, error: err.message })
    };
  }
};