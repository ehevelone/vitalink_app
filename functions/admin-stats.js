// functions/admin-stats.js
const { requireAdmin } = require("./services/_adminAuth");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-token",
  "Access-Control-Allow-Methods": "GET, OPTIONS"
};

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "GET") {
    return { statusCode: 405, headers: corsHeaders, body: "Method Not Allowed" };
  }

  const auth = await requireAdmin(event);
  if (auth.error) {
    return { statusCode: 401, headers: corsHeaders, body: auth.error };
  }

  try {
    const client = await pool.connect();

    // Total RSMs (exclude admin)
    const rsmCount = await client.query(
      "SELECT COUNT(*) FROM rsms WHERE role='rsm'"
    );

    // Total enrolled agents (active only)
    const agentCount = await client.query(
      "SELECT COUNT(*) FROM agents WHERE active=true"
    );

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        total_rsms: Number(rsmCount.rows[0].count),
        total_enrolled_agents: Number(agentCount.rows[0].count)
      })
    };

  } catch (err) {
    console.error("admin-stats error:", err);
    return { statusCode: 500, headers: corsHeaders, body: "Server error" };
  }
};
