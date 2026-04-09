const { Pool } = require("pg");
const crypto = require("crypto");
const { encrypt } = require("./encrypt.js");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false },
});

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body || "{}");

    // 🔥 CHANGED: use UUID id instead of user_id
    const { id, profiles } = body;

    if (!id || !profiles || !Array.isArray(profiles)) {
      return {
        statusCode: 400,
        body: JSON.stringify({
          success: false,
          error: "Missing or invalid id / profiles",
        }),
      };
    }

    console.log("🔥 Saving profiles for UUID:", id);

    let saved = 0;

    for (const p of profiles) {
      const name = (p.fullName || p.name || "").trim();

      if (!name) continue;

      try {
        const profileId = p.id || crypto.randomUUID();
        const encrypted_data = encrypt(JSON.stringify(p));

        const existing = await pool.query(
          `SELECT id, qr_token FROM profiles WHERE id = $1 LIMIT 1`,
          [profileId]
        );

        let token;
        let token_hash;

        if (existing.rows.length) {
          token = existing.rows[0].qr_token;

          token_hash = crypto
            .createHash("sha256")
            .update(token)
            .digest("hex");

        } else {
          token = crypto.randomBytes(16).toString("hex");

          token_hash = crypto
            .createHash("sha256")
            .update(token)
            .digest("hex");
        }

        await pool.query(
          `
          INSERT INTO profiles (
            id,
            user_id,
            name,
            encrypted_data,
            qr_token,
            token_hash,
            qr_revoked,
            created_at
          )
          VALUES ($1,$2,$3,$4,$5,$6,false,NOW())
          ON CONFLICT (id)
          DO UPDATE SET
            name = EXCLUDED.name,
            encrypted_data = EXCLUDED.encrypted_data,
            token_hash = EXCLUDED.token_hash
          `,
          [
            profileId,
            id, // 🔥 THIS IS NOW UUID
            name,
            encrypted_data,
            token,
            token_hash
          ]
        );

        saved++;

      } catch (err) {
        console.error("❌ SAVE FAILED:", err, p);
      }
    }

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        count: saved,
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