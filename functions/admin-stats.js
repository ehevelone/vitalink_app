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

    // 🔥 ONE QUERY → FULL REPORT
    const stats = await client.query(`
      SELECT
        -- 1A: TOTAL RSMS
        (SELECT COUNT(*) FROM rsms WHERE role='rsm') AS total_rsms,

        -- 1B: AGENTS UNDER RSMS
        COUNT(DISTINCT a.id) FILTER (WHERE a.rsm_id IS NOT NULL) AS rsm_agents,

        -- 1C: USERS UNDER THOSE AGENTS
        COUNT(u.id) FILTER (WHERE a.rsm_id IS NOT NULL AND u.agent_id IS NOT NULL) AS rsm_users,

        -- 2A: INDEPENDENT AGENTS
        COUNT(DISTINCT a.id) FILTER (WHERE a.rsm_id IS NULL AND u.agent_id IS NOT NULL) AS independent_agents,

        -- 2B: THEIR USERS
        COUNT(u.id) FILTER (WHERE a.rsm_id IS NULL AND u.agent_id IS NOT NULL) AS independent_agent_users,

        -- 3: INDEPENDENT USERS
        COUNT(u.id) FILTER (WHERE u.agent_id IS NULL) AS independent_users

      FROM users u
      LEFT JOIN agents a ON u.agent_id = a.id
    `);

    client.release();
    client = null;

    const row = stats.rows[0];

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        total_rsms: Number(row.total_rsms),

        rsm_agents: Number(row.rsm_agents),
        rsm_users: Number(row.rsm_users),

        independent_agents: Number(row.independent_agents),
        independent_agent_users: Number(row.independent_agent_users),

        independent_users: Number(row.independent_users)
      })
    };

  } catch (err) {
    console.error("admin-stats error:", err);

    if (client) client.release();

    return { statusCode: 500, headers: corsHeaders, body: "Server error" };
  }
};