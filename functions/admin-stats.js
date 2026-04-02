const { requireAdmin } = require("./_adminAuth");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
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

  let client;

  try {
    client = await pool.connect();

    // ✅ TOTAL RSMS
    const rsmCount = await client.query(`
      SELECT COUNT(*) 
      FROM rsms 
      WHERE role='rsm'
    `);

    // ✅ TOTAL AGENTS (ALL)
    const totalAgents = await client.query(`
      SELECT COUNT(*) 
      FROM agents
    `);

    // ✅ ACTIVE AGENTS
    const activeAgents = await client.query(`
      SELECT COUNT(*) 
      FROM agents 
      WHERE active = true
    `);

    // ✅ INACTIVE AGENTS
    const inactiveAgents = await client.query(`
      SELECT COUNT(*) 
      FROM agents 
      WHERE active = false OR active IS NULL
    `);

    // ✅ FULL BREAKDOWN PER RSM
    const breakdown = await client.query(`
      SELECT 
        r.id,
        r.email,
        COUNT(a.id) AS total_agents,
        COUNT(a.id) FILTER (WHERE a.active = true) AS active_agents,
        COUNT(a.id) FILTER (WHERE a.active = false OR a.active IS NULL) AS inactive_agents
      FROM rsms r
      LEFT JOIN agents a ON a.rsm_id = r.id
      WHERE r.role='rsm'
      GROUP BY r.id
      ORDER BY r.email ASC
    `);

    client.release();
    client = null;

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        total_rsms: Number(rsmCount.rows[0].count),

        // 🔥 FIXED
        total_enrolled_agents: Number(totalAgents.rows[0].count),
        active_agents: Number(activeAgents.rows[0].count),
        inactive_agents: Number(inactiveAgents.rows[0].count),

        breakdown: breakdown.rows
      })
    };

  } catch (err) {
    console.error("admin-stats error:", err);

    if (client) client.release();

    return { statusCode: 500, headers: corsHeaders, body: "Server error" };
  }
};