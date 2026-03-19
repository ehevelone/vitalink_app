// @ts-nocheck

const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

exports.handler = async (event) => {

  // -------------------------
  // CORS
  // -------------------------
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers: corsHeaders,
      body: "Method Not Allowed"
    };
  }

  try {

    // -------------------------
    // AUTH
    // -------------------------
    const token = event.headers.authorization;

    if (!token) {
      return {
        statusCode: 401,
        headers: corsHeaders,
        body: "Missing token"
      };
    }

    const client = await pool.connect();

    // Validate agent session
    const agentRes = await client.query(
      "SELECT id FROM rsms WHERE admin_session_token=$1 LIMIT 1",
      [token]
    );

    if (agentRes.rows.length === 0) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders,
        body: "Invalid session"
      };
    }

    const agentId = agentRes.rows[0].id;

    // -------------------------
    // BODY
    // -------------------------
    const { userId, active } = JSON.parse(event.body || "{}");

    if (!userId || typeof active !== "boolean") {
      client.release();
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Invalid payload"
      };
    }

    // -------------------------
    // SECURITY CHECK
    // Ensure agent OWNS this client
    // -------------------------
    const userCheck = await client.query(
      "SELECT id FROM users WHERE id=$1 AND agent_id=$2 LIMIT 1",
      [userId, agentId]
    );

    if (userCheck.rows.length === 0) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders,
        body: "Unauthorized"
      };
    }

    // -------------------------
    // UPDATE
    // -------------------------
    await client.query(
      "UPDATE users SET active=$1 WHERE id=$2",
      [active, userId]
    );

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        success: true
      })
    };

  } catch (err) {
    console.error("agent-toggle-client error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };
  }

};