// functions/agent-enroll-from-invite.js

const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

function generateAgentCode(prefix = "AGT", length = 8) {

  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";

  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }

  return `${prefix}-${code}`;
}

exports.handler = async function (event) {

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

  const client = await pool.connect();

  try {

    const { name, email, phone, rsm_code } = JSON.parse(event.body || "{}");

    if (!name || !email || !phone || !rsm_code) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Missing required fields"
      };
    }

    /* VALIDATE RSM */

    const rsm = await client.query(
      `SELECT id
       FROM rsms
       WHERE invite_code = $1
       AND role = 'rsm'
       AND active = true
       LIMIT 1`,
      [rsm_code]
    );

    if (rsm.rows.length === 0) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Invalid invite code"
      };
    }

    const rsmId = rsm.rows[0].id;

    /* PREVENT DUPLICATE AGENT */

    const existing = await client.query(
      `SELECT id
       FROM agents
       WHERE LOWER(email) = LOWER($1)
       LIMIT 1`,
      [email]
    );

    if (existing.rows.length > 0) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Agent already exists"
      };
    }

    /* GENERATE AGENT CODE */

    const agentCode = generateAgentCode();

    /* CREATE AGENT */

    const insert = await client.query(
      `INSERT INTO agents
        (name, email, phone, active, created_at, rsm_id, agent_code)
       VALUES
        ($1,$2,$3,true,NOW(),$4,$5)
       RETURNING id, name, email, phone, agent_code`,
      [
        name.trim(),
        email.trim().toLowerCase(),
        phone.trim(),
        rsmId,
        agentCode
      ]
    );

    const agent = insert.rows[0];

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        success: true,
        agent_code: agent.agent_code,
        agent
      })
    };

  } catch (err) {

    console.error("agent-enroll-from-invite error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };

  } finally {

    client.release();

  }

};