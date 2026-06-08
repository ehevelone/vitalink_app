const crypto = require("crypto");
const db = require("./services/db");
const {
  clean,
  cleanupExpiredPackages,
  encrypt,
  ensureSchema,
  normalizeSections,
  parseBody,
  reply,
  sendProfileUpdatePush,
  verifyUserSession,
} = require("./services/profile-share-sync");

const SECTION_KEYS = {
  emergency: ["emergency"],
  medications: ["meds"],
  doctors: ["doctors"],
  appointments: ["appointments"],
  policies: ["insurances"],
  insurance_cards: ["orphanCards"],
};

function filterPayloadForSections(payload, sections) {
  const filtered = {
    profileId: payload.profileId,
    profileName: payload.profileName,
    updatedAt: payload.updatedAt,
  };

  if (payload.profile && typeof payload.profile === "object") {
    filtered.profile = payload.profile;
  }

  for (const section of sections) {
    for (const key of SECTION_KEYS[section] || []) {
      if (payload[key] !== undefined) {
        filtered[key] = payload[key];
      }
    }
  }

  return filtered;
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureSchema();
    await cleanupExpiredPackages();

    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    const sessionToken = clean(body.sessionToken);
    const profileId = clean(body.profileId || body.profile_id);
    const profileName = clean(body.profileName || body.profile_name);
    const allowedSections = normalizeSections(body.allowedSections);
    const payload = body.payload;

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    if (!profileId || !payload || typeof payload !== "object") {
      return reply(400, {
        success: false,
        error: "Missing profile or update payload",
      });
    }

    const recipientsRes = await db.query(
      `
      SELECT id, recipient_user_id, allowed_sections
      FROM profile_share_links
      WHERE owner_user_id = $1
        AND profile_id = $2
        AND status = 'accepted'
        AND recipient_user_id IS NOT NULL
        AND revoked_at IS NULL
      `,
      [userId, profileId]
    );

    if (!recipientsRes.rows.length) {
      return reply(200, {
        success: true,
        message: "No connected recipients for this profile",
        recipients: 0,
      });
    }

    const groups = new Map();

    for (const row of recipientsRes.rows) {
      const rowSections = normalizeSections(row.allowed_sections);
      const effectiveSections = allowedSections.filter(section =>
        rowSections.includes(section)
      );

      if (!effectiveSections.length) {
        continue;
      }

      const key = effectiveSections.join("|");
      const group = groups.get(key) || {
        sections: effectiveSections,
        rows: [],
      };

      group.rows.push(row);
      groups.set(key, group);
    }

    if (!groups.size) {
      return reply(200, {
        success: true,
        message: "No connected recipients have matching share permissions",
        recipients: 0,
      });
    }

    const packageIds = [];
    let recipients = 0;
    const pushes = [];

    for (const group of groups.values()) {
      const packageId = crypto.randomUUID();
      const filteredPayload = filterPayloadForSections(payload, group.sections);
      const encryptedPayload = encrypt(JSON.stringify({
        profileId,
        profileName,
        allowedSections: group.sections,
        payload: filteredPayload,
        createdAt: new Date().toISOString(),
      }));

      await db.query(
        `
        INSERT INTO profile_update_packages (
          id,
          owner_user_id,
          profile_id,
          profile_name,
          allowed_sections,
          encrypted_payload,
          expires_at
        )
        VALUES ($1,$2,$3,$4,$5::jsonb,$6,NOW() + INTERVAL '7 days')
        `,
        [
          packageId,
          userId,
          profileId,
          profileName,
          JSON.stringify(group.sections),
          encryptedPayload,
        ]
      );

      const recipientIds = [];

      for (const row of group.rows) {
        recipients += 1;
        recipientIds.push(row.recipient_user_id);

        await db.query(
          `
          INSERT INTO profile_update_recipients (
            id,
            package_id,
            recipient_user_id,
            share_link_id
          )
          VALUES ($1,$2,$3,$4)
          `,
          [
            crypto.randomUUID(),
            packageId,
            row.recipient_user_id,
            row.id,
          ]
        );
      }

      const push = await sendProfileUpdatePush({
        recipientUserIds: [...new Set(recipientIds)],
        packageId,
        profileName,
      });

      pushes.push(push);

      await db.query(
        `
        UPDATE profile_update_recipients
        SET notified_at = NOW()
        WHERE package_id = $1
        `,
        [packageId]
      );

      packageIds.push(packageId);
    }

    return reply(200, {
      success: true,
      packageIds,
      recipients,
      pushes,
    });
  } catch (err) {
    console.error("create_profile_update_package error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
