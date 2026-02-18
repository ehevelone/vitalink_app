// functions/admin-stats.js
const { requireAdmin } = require("./_adminAuth");
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

    const rsmCount = await client.query(`
      SELECT COUNT(*) 
      FROM rsms 
      WHERE role='rsm'
    `);

    const agentCount = await client.query(`
      SELECT COUNT(*) 
      FROM agents 
      WHERE active=true
    `);

    const breakdown = await client.query(`
      SELECT 
        r.id,
        r.email,
        COUNT(a.id) FILTER (WHERE a.active = true) AS active_agents
      FROM rsms r
      LEFT JOIN agents a ON a.rsm_id = r.id
      WHERE r.role='rsm'
      GROUP BY r.id
      ORDER BY r.email ASC
    `);

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        total_rsms: Number(rsmCount.rows[0].count),
        total_enrolled_agents: Number(agentCount.rows[0].count),
        breakdown: breakdown.rows
      })
    };

  } catch (err) {
    console.error("admin-stats error:", err);
    return { statusCode: 500, headers: corsHeaders, body: "Server error" };
  }
};
