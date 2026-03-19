// @ts-nocheck

const bcrypt = require("bcryptjs");
const crypto = require("crypto");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const DEV_MODE = true;

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

    const result = await client.query(
      "SELECT id, password_hash, phone, role FROM rsms WHERE email = $1 AND active = true LIMIT 1",
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

    // ==========================
    // 🚨 DEV MODE — SKIP 2FA
    // ==========================
    if (DEV_MODE) {

      const sessionToken = crypto.randomBytes(24).toString("hex");
      const expires = new Date(Date.now() + 8 * 60 * 60 * 1000);

      await client.query(
        "UPDATE rsms SET admin_session_token=$1, admin_session_expires=$2 WHERE id=$3",
        [sessionToken, expires, user.id]
      );

      client.release();

      return {
        statusCode: 200,
        headers: corsHeaders(),
        body: JSON.stringify({
          step: "login_success",
          token: sessionToken,
          role: user.role
        })
      };
    }

    // ==========================
    // NORMAL 2FA FLOW
    // ==========================
    if (!user.phone) {
      client.release();
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: "Phone not configured for 2FA"
      };
    }

    let phone = user.phone.replace(/\D/g, "");

    if (phone.length === 10) {
      phone = "+1" + phone;
    } else if (!phone.startsWith("+")) {
      phone = "+" + phone;
    }

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders(),
      body: JSON.stringify({
        step: "firebase_2fa",
        phone: phone,
        role: user.role
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