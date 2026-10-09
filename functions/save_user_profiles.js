const crypto = require("crypto");
const { encrypt } = require("./encrypt.js");
// Shared pool (services/db.js) so this hot endpoint does not open its own.
const pool = require("./services/db");
const { verifyUserSession } = require("./services/user-auth");

// 🔥 NEW: merge insurance entries BEFORE save
function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}


function mergeInsuranceEntries(profile) {
  if (!profile.insurance || !Array.isArray(profile.insurance)) return profile;

  const merged = [];

  for (const incoming of profile.insurance) {
    if (!incoming) continue;

    const matchIndex = merged.findIndex(i =>
      (i.memberId && incoming.memberId && i.memberId === incoming.memberId) ||
      (i.policy && incoming.policy && i.policy === incoming.policy)
    );

    if (matchIndex !== -1) {
      merged[matchIndex] = {
        ...merged[matchIndex],
        ...incoming,
      };
    } else {
      merged.push(incoming);
    }
  }

  profile.insurance = merged;
  return profile;
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    const body = JSON.parse(event.body || "{}");

    // 🔥 CHANGED: use UUID id instead of user_id
    const { id, profiles, sessionToken } = body;

    if (!id || !profiles || !Array.isArray(profiles)) {
      return reply(400, {
        success: false,
        error: "Missing or invalid id / profiles",
      });
    }

    const authorized = await verifyUserSession(id, sessionToken);

    if (!authorized) {
      return reply(403, {
        success: false,
        error: "Unauthorized",
      });
    }

    let saved = 0;

    for (const p of profiles) {
      const name = (p.fullName || p.name || "").trim();

      if (!name) continue;

      try {
        const profileId = p.id || crypto.randomUUID();

        // 🔥 FIX: merge insurance BEFORE encrypting
        const cleanedProfile = mergeInsuranceEntries(p);

        const encrypted_data = encrypt(JSON.stringify(cleanedProfile));

        const existing = await pool.query(
          `SELECT id, user_id, qr_token FROM profiles WHERE id = $1 LIMIT 1`,
          [profileId]
        );

        if (existing.rows.length && String(existing.rows[0].user_id) !== String(id)) {
          console.error("save_user_profiles ownership mismatch", { profileId });
          continue;
        }

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
          WHERE profiles.user_id = EXCLUDED.user_id
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
        console.error("save_user_profiles item failed:", err);
      }
    }

    return reply(200, {
      success: true,
      count: saved,
    });

  } catch (err) {
    console.error("🔥 save_user_profiles error:", err);

    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};
