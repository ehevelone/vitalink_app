// @ts-nocheck

const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

exports.handler = async function (event) {
  try {
    const token = event.headers["x-admin-session"];

    if (!token) {
      return { statusCode: 403, body: JSON.stringify({ error: "Unauthorized" }) };
    }

    const client = await pool.connect();

    const auth = await client.query(
      `SELECT id FROM rsms
       WHERE role = 'admin'
         AND active = true
         AND admin_session_token = $1
         AND admin_session_expires > NOW()
       LIMIT 1`,
      [token]
    );

    if (auth.rows.length === 0) {
      client.release();
      return { statusCode: 403, body: JSON.stringify({ error: "Unauthorized" }) };
    }

    const totalRSMs = await client.query("SELECT COUNT(*) FROM rsms WHERE role = 'rsm'");
    const totalAgents = await client.query("SELECT COUNT(*) FROM agents");
    const activeAgents = await client.query("SELECT COUNT(*) FROM agents WHERE active = true");
    const totalUsers = await client.query("SELECT COUNT(*) FROM users");
    const totalDevices = await client.query("SELECT COUNT(*) FROM user_devices");

    client.release();

    return {
      statusCode: 200,
      body: JSON.stringify({
        totalRSMs: parseInt(totalRSMs.rows[0].count),
        totalAgents: parseInt(totalAgents.rows[0].count),
        activeAgents: parseInt(activeAgents.rows[0].count),
        totalUsers: parseInt(totalUsers.rows[0].count),
        totalProfiles: parseInt(totalDevices.rows[0].count),
        totalScans: 0
      })
    };

  } catch (err) {
    console.error("admin-stats error:", err);
    return { statusCode: 500, body: JSON.stringify({ error: "Server error" }) };
  }
};
