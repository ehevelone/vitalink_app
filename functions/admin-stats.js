const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

exports.handler = async function () {
  try {
    const client = await pool.connect();

    const totalRSMs = await client.query("SELECT COUNT(*) FROM rsms");
    const totalAgents = await client.query("SELECT COUNT(*) FROM agents");
    const activeAgents = await client.query(
      "SELECT COUNT(*) FROM agents WHERE active = true"
    );
    const totalUsers = await client.query("SELECT COUNT(*) FROM users");
    const totalProfiles = await client.query("SELECT COUNT(*) FROM profiles");
    const totalScans = await client.query("SELECT COUNT(*) FROM qr_scans");

    client.release();

    return {
      statusCode: 200,
      body: JSON.stringify({
        totalRSMs: parseInt(totalRSMs.rows[0].count),
        totalAgents: parseInt(totalAgents.rows[0].count),
        activeAgents: parseInt(activeAgents.rows[0].count),
        totalUsers: parseInt(totalUsers.rows[0].count),
        totalProfiles: parseInt(totalProfiles.rows[0].count),
        totalScans: parseInt(totalScans.rows[0].count)
      })
    };

  } catch (err) {
    console.error("Admin stats error:", err);

    return {
      statusCode: 500,
      body: JSON.stringify({ error: err.message })
    };
  }
};
