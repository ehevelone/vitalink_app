const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false },
});

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");

    const { user_id, profiles } = body;

    if (!user_id || !profiles) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          success: false,
          error: "Missing user_id or profiles",
        }),
      };
    }

    // 🔥 Save FULL profile list (overwrite)
    await pool.query(
      `
      UPDATE users
      SET profiles = $1,
          updated_at = NOW()
      WHERE id = $2
      `,
      [JSON.stringify(profiles), user_id]
    );

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
      }),
    };

  } catch (err) {
    console.error("save_user_profiles error:", err);

    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        error: "Server error",
      }),
    };
  }
};