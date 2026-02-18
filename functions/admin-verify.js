// @ts-nocheck

const crypto = require("crypto");
const admin = require("firebase-admin");
const { Pool } = require("pg");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(
      JSON.parse(process.env.FCM_SERVICE_ACCOUNT)
    )
  });
}

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
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
    const { idToken, email } = JSON.parse(event.body || "{}");

    if (!idToken || !email) {
      return { statusCode: 400, headers: corsHeaders, body: "Missing data" };
    }

    const decoded = await admin.auth().verifyIdToken(idToken);

    if (!decoded.phone_number) {
      return { statusCode: 403, headers: corsHeaders, body: "Phone verification required" };
    }

    const client = await pool.connect();

    // 🔥 Allow BOTH admin and rsm
    const result = await client.query(
      "SELECT id, phone, role FROM rsms WHERE email=$1 AND active=true LIMIT 1",
      [email]
    );

    if (result.rows.length === 0) {
      client.release();
      return { statusCode: 403, headers: corsHeaders, body: "Unauthorized" };
    }

    const user = result.rows[0];

    const dbPhone = String(user.phone).replace(/\D/g, "");
    const firebasePhone = String(decoded.phone_number).replace(/\D/g, "");

    if (dbPhone !== firebasePhone) {
      client.release();
      return { statusCode: 403, headers: corsHeaders, body: "Phone mismatch" };
    }

    const sessionToken = crypto.randomBytes(24).toString("hex");
    const expires = new Date(Date.now() + 8 * 60 * 60 * 1000);

    await client.query(
      "UPDATE rsms SET admin_session_token=$1, admin_session_expires=$2 WHERE id=$3",
      [sessionToken, expires, user.id]
    );

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        success: true,
        token: sessionToken,
        role: user.role   // 🔥 CRITICAL FIX
      })
    };

  } catch (err) {
    console.error("admin-verify error:", err);
    return { statusCode: 500, headers: corsHeaders, body: "Verification failed" };
  }
};
