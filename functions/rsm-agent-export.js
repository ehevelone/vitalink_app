const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Content-Type": "application/json"
};

function reply(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify(body)
  };
}

exports.handler = async function(event) {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "GET") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  const sessionToken =
    event.headers["x-admin-session"] ||
    event.headers["X-Admin-Session"];
  const agentId = event.queryStringParameters?.id;

  if (!sessionToken) {
    return reply(401, { success: false, error: "Missing session" });
  }

  if (!agentId) {
    return reply(400, { success: false, error: "Missing agent id" });
  }

  const client = await pool.connect();

  try {
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

    if (!rsmResult.rows.length) {
      return reply(401, { success: false, error: "Invalid session" });
    }

    const agentResult = await client.query(
      `
      SELECT id, name, email, phone, active, created_at
      FROM agents
      WHERE id = $1
        AND rsm_id = $2
      LIMIT 1
      `,
      [Number(agentId), rsmResult.rows[0].id]
    );

    if (!agentResult.rows.length) {
      return reply(404, { success: false, error: "Agent not found" });
    }

    return reply(200, {
      success: true,
      ...agentResult.rows[0]
    });
  } catch (err) {
    console.error("rsm-agent-export error:", err);
    return reply(500, { success: false, error: "Server error" });
  } finally {
    client.release();
  }
};
