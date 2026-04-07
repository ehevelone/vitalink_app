const { Pool } = require("pg");
const crypto = require("crypto");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false },
});

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");

    const { user_id, profiles } = body;

    if (!user_id || !profiles || !Array.isArray(profiles)) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          success: false,
          error: "Missing or invalid user_id / profiles",
        }),
      };
    }

    console.log("🔥 Saving profiles for user:", user_id);
    console.log("📦 Profiles received:", profiles);

    // 🔥 STEP 1 — CLEAR EXISTING PROFILES
    await pool.query(
      `DELETE FROM profiles WHERE user_id = $1`,
      [user_id]
    );

    let inserted = 0;

    // 🔥 STEP 2 — INSERT FULL PROFILE DATA
    for (const p of profiles) {
      const name = (p.fullName || p.name || "").trim();

      if (!name) {
        console.log("⚠️ Skipping empty profile:", p);
        continue;
      }

      try {
        // ✅ CREATE UUID
        const id = crypto.randomUUID();

        await pool.query(
          `
          INSERT INTO profiles (
            id,
            user_id,
            name,
            raw_data,
            created_at,
            updated_at
          )
          VALUES ($1,$2,$3,$4,NOW(),NOW())
          `,
          [
            id,
            user_id,
            name,
            JSON.stringify(p) // 🔥 THIS is your entire system now
          ]
        );

        inserted++;

      } catch (err) {
        console.error("❌ INSERT FAILED:", err, p);
      }
    }

    console.log("✅ Inserted profiles:", inserted);

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        count: inserted,
      }),
    };

  } catch (err) {
    console.error("🔥 save_user_profiles error:", err);

    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        error: err.message || "Server error",
      }),
    };
  }
};