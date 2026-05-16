const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

async function requireAdmin(event) {
  try {

    // ✅ FIXED HEADER
    const token =
      event.headers["x-admin-session"] ||
      event.headers["X-Admin-Session"]; // fallback for case issues

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

    const user = result.rows[0];

    if (user.role !== "admin") {
      return { error: "Not authorized" };
    }

    if (new Date(user.admin_session_expires) < new Date()) {
      return { error: "Session expired" };
    }

    return { admin: user };

  } catch (err) {
    console.error("Admin auth error:", err);
    return { error: "Auth failure" };
  }
}

async function requireRole(event, allowedRoles) {
  try {
    const token =
      event.headers["x-admin-session"] ||
      event.headers["X-Admin-Session"] ||
      event.headers["x-rsm-token"] ||
      event.headers["X-RSM-TOKEN"];

    if (!token) {
      return { error: "Missing session token" };
    }

    const client = await pool.connect();

    const result = await client.query(
      `
      SELECT id, email, role, billing_active, invite_code, admin_session_expires
      FROM rsms
      WHERE admin_session_token=$1
      LIMIT 1
      `,
      [token]
    );

    client.release();

    if (result.rows.length === 0) {
      return { error: "Invalid session" };
    }

    const user = result.rows[0];

    if (new Date(user.admin_session_expires) < new Date()) {
      return { error: "Session expired" };
    }

    if (!allowedRoles.includes(user.role)) {
      return { error: "Not authorized" };
    }

    return { user };
  } catch (err) {
    console.error("Admin role auth error:", err);
    return { error: "Auth failure" };
  }
}

async function requireRsm(event) {
  const auth = await requireRole(event, ["rsm"]);
  return auth.error ? { error: auth.error } : { rsm: auth.user };
}

async function requireAdminOrRsm(event) {
  return requireRole(event, ["admin", "rsm"]);
}

module.exports = { requireAdmin, requireRsm, requireAdminOrRsm };
