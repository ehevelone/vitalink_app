// @ts-nocheck

const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

exports.handler = async function (event) {
  try {
    if (event.httpMethod !== "POST") {
      return { statusCode: 405, body: "Method Not Allowed" };
    }

    const token = event.headers["x-admin-session"];
    if (!token) return { statusCode: 200, body: JSON.stringify({ success: true }) };

    const client = await pool.connect();

    await client.query(
      "UPDATE rsms SET admin_session_token = NULL, admin_session_expires = NULL WHERE role='admin' AND admin_session_token=$1",
      [token]
    );

    client.release();

    return { statusCode: 200, body: JSON.stringify({ success: true }) };
  } catch (err) {
    console.error("admin-logout error:", err);
    return { statusCode: 500, body: JSON.stringify({ error: "Server error" }) };
  }
};
