// functions/services/_adminAuth.js
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

async function requireAdmin(event) {
  try {
    const token = event.headers["x-admin-token"];

    if (!token) {
      return { error: "Missing session token" };
    }

    const client = await pool.connect();

    const result = await client.query(
      "SELECT id, role, admin_session_expires FROM rsms WHERE admin_session_token=$1 LIMIT 1",
      [token]
    );

    client.release();

    if (result.rows.length === 0) {
      return { error: "Invalid session" };
    }

    const adminUser = result.rows[0];

    if (adminUser.role !== "admin") {
      return { error: "Not authorized" };
    }

    if (new Date(adminUser.admin_session_expires) < new Date()) {
      return { error: "Session expired" };
    }

    return { admin: adminUser };

  } catch (err) {
    console.error("Admin auth error:", err);
    return { error: "Auth failure" };
  }
}

module.exports = { requireAdmin };
