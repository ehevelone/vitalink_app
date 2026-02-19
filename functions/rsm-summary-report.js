// functions/rsm-summary-report.js
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-rsm-token",
  "Access-Control-Allow-Methods": "GET, OPTIONS"
};

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "GET") {
    return { statusCode: 405, headers: corsHeaders, body: "Method Not Allowed" };
  }

  try {

    const token = event.headers["x-rsm-token"];
    if (!token) {
      return { statusCode: 401, headers: corsHeaders, body: "Missing token" };
    }

    const client = await pool.connect();

    // 🔐 Validate RSM session
    const rsmResult = await client.query(`
      SELECT id
      FROM rsms
      WHERE admin_session_token = $1
      AND role = 'rsm'
      AND admin_session_expires > NOW()
      LIMIT 1
    `, [token]);

    if (rsmResult.rows.length === 0) {
      client.release();
      return { statusCode: 401, headers: corsHeaders, body: "Invalid session" };
    }

    const rsmId = rsmResult.rows[0].id;

    const search = event.queryStringParameters?.search || "";

    // 🔎 Agent Search
    const agents = await client.query(`
      SELECT id, name, email, active, created_at
      FROM agents
      WHERE rsm_id = $1
      AND (
        $2 = '' OR
        LOWER(name) LIKE LOWER($2) OR
        LOWER(email) LIKE LOWER($2)
      )
      ORDER BY created_at DESC
    `, [rsmId, `%${search}%`]);

    // 📊 Count
    const count = await client.query(`
      SELECT COUNT(*)
      FROM agents
      WHERE rsm_id = $1
      AND active = true
    `, [rsmId]);

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        active_agents: Number(count.rows[0].count),
        agents: agents.rows
      })
    };

  } catch (err) {
    console.error("rsm-summary-report error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };
  }
};
