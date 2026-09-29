const db = require("./services/db");
const { decrypt } = require("./encrypt");
const { verifyUserSession } = require("./services/user-auth");

function reply(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(body),
  };
}

function text(value) {
  return String(value || "").trim();
}

function selectUserDemographics(account = {}, profile = {}) {
  const accountName = [account.first_name, account.last_name]
    .map(text)
    .filter(Boolean)
    .join(" ");

  return {
    email: text(account.email),
    fullName: text(profile.fullName || profile.name) || accountName,
    userPhone: text(profile.userPhone || profile.phone) || text(account.phone),
    dob: text(profile.dob),
    address: text(profile.address),
    city: text(profile.city),
    state: text(profile.state),
    zip: text(profile.zip),
    isVeteran:
      profile.isVeteran === true ||
      profile.is_veteran === true ||
      profile.veteran === true,
    usesVaHealthcare:
      profile.usesVaHealthcare === true ||
      profile.uses_va_healthcare === true,
  };
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") return reply(200, {});
  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  try {
    const body = JSON.parse(event.body || "{}");
    const userId = text(body.userId);
    const sessionToken = text(body.sessionToken);
    const profileId = text(body.profileId);

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const accountResult = await db.query(
      `SELECT id, email, first_name, last_name, phone
       FROM users
       WHERE id = $1
       LIMIT 1`,
      [userId],
    );
    if (!accountResult.rows.length) {
      return reply(404, { success: false, error: "User not found" });
    }

    const profileResult = await db.query(
      `SELECT id, encrypted_data
       FROM profiles
       WHERE user_id = $1
       ORDER BY (id::text = $2) DESC, created_at DESC`,
      [userId, profileId],
    );

    let savedProfile = {};
    for (const row of profileResult.rows) {
      if (!row.encrypted_data) continue;
      try {
        savedProfile = JSON.parse(decrypt(row.encrypted_data));
        break;
      } catch (error) {
        console.warn(
          `Could not decrypt profile ${row.id} for demographic recovery:`,
          error.message,
        );
      }
    }

    return reply(200, {
      success: true,
      demographics: selectUserDemographics(
        accountResult.rows[0],
        savedProfile,
      ),
    });
  } catch (error) {
    console.error("get_user_demographics error:", error);
    return reply(500, {
      success: false,
      error: "Could not load registration demographics",
    });
  }
};

exports.selectUserDemographics = selectUserDemographics;
