// FORCE REDEPLOY - bcryptjs only - 2026-02-23
// functions/rsm-login.js
const crypto = require("crypto");
const { Pool } = require("pg");
const bcrypt = require("bcryptjs");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const SITE = "https://myvitalink.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json", ...corsHeaders },
    body: JSON.stringify(obj),
  };
}

exports.handler = async function (event) {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  let body = {};
  try {
    body = JSON.parse(event.body || "{}");
  } catch {
    return reply(400, { success: false, error: "Invalid request body" });
  }

  const email = (body.email || "").trim().toLowerCase();
  const password = body.password || "";

  if (!email || !password) {
    return reply(400, { success: false, error: "Email and password required" });
  }

  const client = await pool.connect();

  try {
    const rsmRes = await client.query(
      `
      SELECT id, email, password_hash, role, active
      FROM rsms
      WHERE LOWER(email) = LOWER($1)
      AND role = 'rsm'
      LIMIT 1
      `,
      [email]
    );

    if (rsmRes.rows.length === 0) {
      return reply(401, { success: false, error: "Invalid credentials" });
    }

    const rsm = rsmRes.rows[0];

    if (!rsm.password_hash || rsm.password_hash === "PENDING_SETUP") {
      return reply(403, {
        success: false,
        error: "Account not set up yet.",
      });
    }

    const ok = await bcrypt.compare(password, rsm.password_hash);
    if (!ok) {
      return reply(401, { success: false, error: "Invalid credentials" });
    }

    const token = crypto.randomBytes(24).toString("hex");
    const expires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await client.query(
      `
      UPDATE rsms
      SET admin_session_token = $1,
          admin_session_expires = $2
      WHERE id = $3
      `,
      [token, expires, rsm.id]
    );

    return reply(200, {
      success: true,
      token,
      rsm: {
        id: rsm.id,
        email: rsm.email,
      },
    });

  } catch (err) {
    console.error("rsm-login error:", err);
    return reply(500, { success: false, error: "Server error" });
  } finally {
    client.release();
  }
};