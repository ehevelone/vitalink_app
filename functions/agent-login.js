// @ts-nocheck

const bcrypt = require("bcryptjs");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: corsHeaders(),
      body: ""
    };
  }

  try {

    if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        headers: corsHeaders(),
        body: "Method Not Allowed"
      };
    }

    const { email, password } = JSON.parse(event.body || "{}");

    if (!email || !password) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: "Missing credentials"
      };
    }

    const client = await pool.connect();

    // 🔥 FIX: USE agents TABLE (NOT rsms)
    const result = await client.query(
      `
      SELECT id, password_hash, name
      FROM agents
      WHERE email = $1 AND active = true
      LIMIT 1
      `,
      [email]
    );

    if (result.rows.length === 0) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: "Unauthorized"
      };
    }

    const user = result.rows[0];

    const valid = await bcrypt.compare(password, user.password_hash);

    if (!valid) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: "Unauthorized"
      };
    }

    client.release();

    // ✅ CLEAN LOGIN RESPONSE
    return {
      statusCode: 200,
      headers: corsHeaders(),
      body: JSON.stringify({
        step: "login_success",
        token: "dev-token",
        agent: {
          id: user.id,
          name: user.name || ""
        }
      })
    };

  } catch (err) {
    console.error("agent-login error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders(),
      body: "Server error"
    };
  }
};

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };
}