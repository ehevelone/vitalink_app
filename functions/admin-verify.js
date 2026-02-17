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

exports.handler = async function (event) {

  // 🔥 REQUIRED CORS HEADERS
  const headers = {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };

  // Handle preflight
  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: ""
    };
  }

  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers,
      body: "Method Not Allowed"
    };
  }

  try {

    const { idToken, email } = JSON.parse(event.body || "{}");

    if (!idToken || !email) {
      return {
        statusCode: 400,
        headers,
        body: "Missing data"
      };
    }

    // 🔐 Verify Firebase ID token
    const decoded = await admin.auth().verifyIdToken(idToken);

    if (!decoded.phone_number) {
      return {
        statusCode: 403,
        headers,
        body: "Phone verification required"
      };
    }

    const client = await pool.connect();

    const result = await client.query(
      "SELECT id, phone FROM rsms WHERE email=$1 AND role='admin' AND active=true LIMIT 1",
      [email]
    );

    if (result.rows.length === 0) {
      client.release();
      return {
        statusCode: 403,
        headers,
        body: "Unauthorized"
      };
    }

    const adminUser = result.rows[0];

    // Normalize phone comparison
    const dbPhone = String(adminUser.phone).replace(/\D/g, "");
    const firebasePhone = String(decoded.phone_number).replace(/\D/g, "");

    if (dbPhone !== firebasePhone) {
      client.release();
      return {
        statusCode: 403,
        headers,
        body: "Phone mismatch"
      };
    }

    // ✅ Create secure session
    const sessionToken = crypto.randomBytes(24).toString("hex");
    const expires = new Date(Date.now() + 8 * 60 * 60 * 1000); // 8 hours

    await client.query(
      "UPDATE rsms SET admin_session_token=$1, admin_session_expires=$2 WHERE id=$3",
      [sessionToken, expires, adminUser.id]
    );

    client.release();

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        token: sessionToken
      })
    };

  } catch (err) {
    console.error("admin-verify error:", err);
    return {
      statusCode: 500,
      headers,
      body: "Verification failed"
    };
  }
};
