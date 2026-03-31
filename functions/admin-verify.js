// @ts-nocheck

const crypto = require("crypto");
const admin = require("firebase-admin");
const { Pool } = require("pg");

/* INIT FIREBASE (SAFE ENV ONLY) */
if (!admin.apps.length) {
  try {

    if (
      !process.env.FIREBASE_PROJECT_ID ||
      !process.env.FIREBASE_CLIENT_EMAIL ||
      !process.env.FIREBASE_PRIVATE_KEY
    ) {
      console.error("❌ FIREBASE ENV MISSING");
      throw new Error("Firebase ENV not set");
    }

    let privateKey = process.env.FIREBASE_PRIVATE_KEY;

    if (privateKey.includes("\\n")) {
      privateKey = privateKey.replace(/\\n/g, "\n");
    }

    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: privateKey
      })
    });

    console.log("✅ Firebase initialized");

  } catch (err) {
    console.error("🔥 Firebase init crash:", err);
    throw err;
  }
}

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers: corsHeaders,
      body: JSON.stringify({ error: "Method Not Allowed" })
    };
  }

  try {

    const { idToken, email } = JSON.parse(event.body || "{}");

    if (!idToken || !email) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: JSON.stringify({ error: "Missing data" })
      };
    }

    const decoded = await admin.auth().verifyIdToken(idToken);

    if (!decoded.phone_number) {
      return {
        statusCode: 403,
        headers: corsHeaders,
        body: JSON.stringify({ error: "Phone verification required" })
      };
    }

    const client = await pool.connect();

    const result = await client.query(
      "SELECT id, phone, role FROM rsms WHERE email=$1 AND active=true LIMIT 1",
      [email]
    );

    if (result.rows.length === 0) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders,
        body: JSON.stringify({ error: "Unauthorized" })
      };
    }

    const user = result.rows[0];

    function normalizePhone(p) {
      let digits = String(p || "").replace(/\D/g, "");
      if (digits.length === 11 && digits.startsWith("1")) {
        digits = digits.slice(1);
      }
      return digits;
    }

    const dbPhone = normalizePhone(user.phone);
    const firebasePhone = normalizePhone(decoded.phone_number);

    if (dbPhone !== firebasePhone) {
      client.release();
      return {
        statusCode: 403,
        headers: corsHeaders,
        body: JSON.stringify({ error: "Phone mismatch" })
      };
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
        role: user.role
      })
    };

  } catch (err) {
    console.error("admin-verify error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: "Verification failed" })
    };
  }

};