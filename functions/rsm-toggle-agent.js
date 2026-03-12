// @ts-nocheck

const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers: corsHeaders, body: "Method Not Allowed" };
  }

  try {

    const sessionToken = event.headers["x-admin-session"];

    if (!sessionToken) {
      return { statusCode: 401, headers: corsHeaders, body: "Unauthorized" };
    }

    const { agentId } = JSON.parse(event.body || "{}");

    if (!agentId) {
      return { statusCode: 400, headers: corsHeaders, body: "Missing agentId" };
    }

    const client = await pool.connect();

    // Verify RSM session
    const rsmCheck = await client.query(
      `SELECT id
       FROM rsms
       WHERE admin_session_token = $1
       AND admin_session_expires > NOW()
       LIMIT 1`,
      [sessionToken]
    );

    if (rsmCheck.rows.length === 0) {
      client.release();
      return { statusCode: 401, headers: corsHeaders, body: "Invalid session" };
    }

    // Toggle agent active status
    const update = await client.query(
      `UPDATE agents
       SET active = NOT active
       WHERE id = $1
       RETURNING id, active`,
      [agentId]
    );

    client.release();

    if (update.rows.length === 0) {
      return { statusCode: 404, headers: corsHeaders, body: "Agent not found" };
    }

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        success: true,
        agent: update.rows[0]
      })
    };

  } catch (err) {
    console.error("toggle-agent error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };
  }

};