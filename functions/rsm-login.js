// FORCE REDEPLOY - bcryptjs only - 2026-02-23
// functions/rsm-login.js
const { Pool } = require("pg");
const { hashPassword, verifyPassword } = require("./services/passwords");

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
      SELECT id, email, password_hash, role, active, phone
      FROM rsms
      WHERE LOWER(TRIM(email)) = LOWER($1)
        AND LOWER(role) IN ('admin', 'rsm')
      LIMIT 1
      `,
      [email]
    );

    if (rsmRes.rows.length === 0) {
      console.log("rsm-login rejected: email not found", {
        email,
      });
      return reply(401, {
        success: false,
        error: "Invalid credentials",
        code: "email_not_found",
      });
    }

    const rsm = rsmRes.rows[0];
    const role = String(rsm.role || "").toLowerCase();

    if (!rsm.password_hash || rsm.password_hash === "PENDING_SETUP") {
      console.log("rsm-login rejected: account setup incomplete", {
        id: rsm.id,
        email: rsm.email,
        role,
      });
      return reply(403, {
        success: false,
        error: "Account not set up yet.",
        code: "setup_incomplete",
      });
    }

    let passwordCheck = await verifyPassword(password, rsm.password_hash);
    let ok = passwordCheck.valid;
    const trimmedPassword = String(password).trim();

    if (!ok && trimmedPassword && trimmedPassword !== password) {
      passwordCheck = await verifyPassword(trimmedPassword, rsm.password_hash);
      ok = passwordCheck.valid;
    }

    if (!ok) {
      console.log("rsm-login rejected: password mismatch", {
        id: rsm.id,
        email: rsm.email,
        role,
        active: rsm.active,
        passwordLength: String(password).length,
        trimmedPasswordLength: trimmedPassword.length,
      });
      return reply(401, {
        success: false,
        error: "Invalid credentials",
        code: "password_mismatch",
      });
    }

    if (passwordCheck.legacy) {
      await client.query(
        "UPDATE rsms SET password_hash = $1 WHERE id = $2",
        [await hashPassword(trimmedPassword || password), rsm.id]
      );
    }

    if (rsm.active !== true) {
      console.log("rsm-login rejected: inactive account", {
        id: rsm.id,
        email: rsm.email,
        role,
      });
      return reply(403, {
        success: false,
        error: "Account is inactive",
        code: "account_inactive",
      });
    }

    if (!rsm.phone) {
      console.log("rsm-login rejected: phone missing", {
        id: rsm.id,
        email: rsm.email,
        role,
      });
      return reply(400, {
        success: false,
        error: "Phone not configured",
        code: "phone_missing",
      });
    }

    console.log("rsm-login password verified, 2FA required", {
      id: rsm.id,
      email: rsm.email,
      role,
      active: rsm.active,
    });

    return reply(200, {
      success: true,
      step: "firebase_2fa",
      phone: rsm.phone,
      role,
    });

  } catch (err) {
    console.error("rsm-login error:", err);
    return reply(500, { success: false, error: "Server error" });
  } finally {
    client.release();
  }
};
