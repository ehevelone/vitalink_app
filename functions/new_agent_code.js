// functions/new_agent_code.js
const db = require("./services/db");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type, x-rsm-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

function generateUnlockCode() {
  return Array.from({ length: 8 }, () =>
    Math.floor(Math.random() * 36).toString(36).toUpperCase()
  ).join("");
}

exports.handler = async (event) => {
  try {

    // ✅ Handle CORS preflight
    if (event.httpMethod === "OPTIONS") {
      return {
        statusCode: 200,
        headers: corsHeaders,
        body: ""
      };
    }

    if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        headers: corsHeaders,
        body: JSON.stringify({ success: false, error: "Method Not Allowed" })
      };
    }

    const rsmToken = event.headers["x-rsm-token"];

    if (!rsmToken) {
      return {
        statusCode: 401,
        headers: corsHeaders,
        body: JSON.stringify({ success: false, error: "Missing RSM session" })
      };
    }

    const client = await pool.connect();

    const rsmResult = await client.query(`
      SELECT id
      FROM rsms
      WHERE admin_session_token = $1
      AND role = 'rsm'
      AND admin_session_expires > NOW()
      LIMIT 1
    `, [rsmToken]);

    if (rsmResult.rows.length === 0) {
      client.release();
      return {
        statusCode: 401,
        headers: corsHeaders,
        body: JSON.stringify({ success: false, error: "Invalid RSM session" })
      };
    }

    const rsmId = rsmResult.rows[0].id;
    client.release();

    const unlockCode = generateUnlockCode();

    const agentResult = await db.query(`
      INSERT INTO agents (unlock_code, active, role, rsm_id, created_at)
      VALUES ($1, FALSE, 'agent', $2, NOW())
      RETURNING id
    `, [unlockCode, rsmId]);

    const agentId = agentResult.rows[0].id;

    return {
      statusCode: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        success: true,
        agentId,
        unlockCode
      })
    };

  } catch (err) {
    console.error("❌ new_agent_code error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ success: false, error: err.message })
    };
  }
};