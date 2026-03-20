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

    const client = await pool.connect();

    // -------------------------
    // BODY (🔥 FIXED)
    // -------------------------
    const body = JSON.parse(event.body || "{}");

    const userId = body.clientId || body.userId;
    const agentId = body.agentId; // 🔥 NOW USED INSTEAD OF BROKEN TOKEN

    if (!userId || !agentId) {
      client.release();
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Missing userId or agentId"
      };
    }

    // -------------------------
    // SECURITY CHECK (VALID AGENT → USER)
    // -------------------------
    const userCheck = await client.query(
      "SELECT id, active FROM users WHERE id=$1 AND agent_id=$2 LIMIT 1",
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

    // 🔥 CURRENT STATUS
    const currentStatus = userCheck.rows[0].active;

    // 🔥 TOGGLE
    const newStatus = !currentStatus;

    // -------------------------
    // UPDATE
    // -------------------------
    await client.query(
      "UPDATE users SET active=$1 WHERE id=$2",
      [newStatus, userId]
    );

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        success: true,
        active: newStatus
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