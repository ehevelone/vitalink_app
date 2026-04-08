const { Pool } = require("pg");
const crypto = require("crypto");
const { encrypt } = require("./encrypt.js"); // ✅ FIXED

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

    await pool.query(
      `DELETE FROM profiles WHERE user_id = $1`,
      [user_id]
    );

    let inserted = 0;

    for (const p of profiles) {
      const name = (p.fullName || p.name || "").trim();

      if (!name) {
        console.log("⚠️ Skipping empty profile:", p);
        continue;
      }

      try {
        const id = crypto.randomUUID();

        const encrypted_data = encrypt(JSON.stringify(p));

        // 🔥 GENERATE TOKEN
        const token = crypto.randomBytes(16).toString("hex");

        const token_hash = crypto
          .createHash("sha256")
          .update(token)
          .digest("hex");

        await pool.query(
          `
          INSERT INTO profiles (
            id,
            user_id,
            name,
            encrypted_data,
            token_hash,
            qr_revoked,
            created_at
          )
          VALUES ($1,$2,$3,$4,$5,$6,NOW())
          `,
          [
            id,
            user_id,
            name,
            encrypted_data,
            token_hash,
            false
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