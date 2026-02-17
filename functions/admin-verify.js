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
  try {
    if (event.httpMethod !== "POST") {
      return { statusCode: 405, body: "Method Not Allowed" };
    }

    const { idToken, email } = JSON.parse(event.body || "{}");

    if (!idToken || !email) {
      return { statusCode: 400, body: "Missing data" };
    }

    // 🔐 Verify Firebase ID token
    const decoded = await admin.auth().verifyIdToken(idToken);

    if (!decoded.phone_number) {
      return { statusCode: 403, body: "Phone verification required" };
    }

    const client = await pool.connect();

    const result = await client.query(
      "SELECT id, phone FROM rsms WHERE email=$1 AND role='admin' AND active=true LIMIT 1",
      [email]
    );

    if (result.rows.length === 0) {
      client.release();
      return { statusCode: 403, body: "Unauthorized" };
    }

    const adminUser = result.rows[0];

    // Normalize phone comparison
    const dbPhone = String(adminUser.phone).replace(/\D/g, "");
    const firebasePhone = String(decoded.phone_number).replace(/\D/g, "");

    if (dbPhone !== firebasePhone) {
      client.release();
      return { statusCode: 403, body: "Phone mismatch" };
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
      body: JSON.stringify({
        success: true,
        token: sessionToken
      })
    };

  } catch (err) {
    console.error("admin-verify error:", err);
    return {
      statusCode: 500,
      body: "Verification failed"
    };
  }
};
