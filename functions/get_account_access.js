const db = require("./services/db");
const { verifyUserSession } = require("./services/user-auth");
const {
  AGREEMENT_VERSION,
  MESSAGING_CONSENT_VERSION,
  PROSPECT_CATEGORIES,
  PROSPECT_CONSENT_VERSION,
  ensureAccountAccessSchema,
  prospectConsentText,
} = require("./services/account-access");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(statusCode, body) {
  return { statusCode, headers, body: JSON.stringify(body) };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });

    const body = JSON.parse(event.body || "{}");
    const userId = body.userId || body.user_id;
    if (!(await verifyUserSession(userId, body.sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    await ensureAccountAccessSchema();

    const result = await db.query(
      `SELECT u.id, u.agent_id, u.access_sponsor, u.relationship_status,
              u.messaging_consent_status, u.messaging_consent_version,
              u.user_agreement_version, u.access_prompted_at,
              u.access_prompt_count, u.purchase_code,
              a.name AS agent_name, a.agency_name, a.active AS agent_active
       FROM users u
       LEFT JOIN agents a ON a.id = u.agent_id
       WHERE u.id = $1
       LIMIT 1`,
      [userId]
    );

    if (!result.rows.length) return reply(404, { success: false, error: "Account not found" });
    const row = result.rows[0];
    const hasAccess = row.access_sponsor === "personal" ||
      (row.access_sponsor === "agent" && row.agent_active === true);
    const agreementCurrent = row.user_agreement_version === AGREEMENT_VERSION;
    const relationshipNeedsConfirmation =
      row.access_sponsor === "agent" &&
      !["confirmed_client", "confirmed_prospect"].includes(row.relationship_status);
    const promptedAt = row.access_prompted_at ? new Date(row.access_prompted_at) : null;
    const promptCount = Number(row.access_prompt_count || 0);
    const repromptDays = promptCount <= 1
      ? 7
      : promptCount === 2
        ? 14
        : promptCount === 3
          ? 30
          : null;
    const promptDue = repromptDays !== null &&
      (!promptedAt || Date.now() - promptedAt.getTime() >= repromptDays * 24 * 60 * 60 * 1000);
    const messagingNeedsPrompt =
      row.relationship_status === "confirmed_client" &&
      ((row.messaging_consent_status === "granted" &&
        row.messaging_consent_version !== MESSAGING_CONSENT_VERSION) ||
        row.messaging_consent_status === "pending" ||
        (row.messaging_consent_status === "deferred" && promptDue));

    const prospectConsentRows = row.agent_id
      ? await db.query(
        `SELECT category,
                CASE WHEN status='granted' AND expires_at <= NOW() THEN 'expired' ELSE status END AS status,
                consent_version, granted_at, withdrawn_at, expires_at
         FROM prospect_marketing_consents
         WHERE user_id=$1 AND agent_id=$2`,
        [userId, row.agent_id]
      )
      : { rows: [] };
    const prospectConsents = {};
    const prospectOptions = {};
    for (const category of Object.keys(PROSPECT_CATEGORIES)) {
      const consent = prospectConsentRows.rows.find((item) => item.category === category);
      prospectConsents[category] = consent || {
        category,
        status: "pending",
        consent_version: PROSPECT_CONSENT_VERSION,
      };
      prospectOptions[category] = {
        category,
        label: PROSPECT_CATEGORIES[category].label,
        durationDays: PROSPECT_CATEGORIES[category].durationDays,
        text: prospectConsentText(category, row.agent_name),
      };
    }

    return reply(200, {
      success: true,
      access: {
        hasAccess,
        sponsor: row.access_sponsor,
        relationshipStatus: row.relationship_status,
        messagingConsentStatus: row.messaging_consent_status,
        messagingConsentCurrent:
          row.messaging_consent_version === MESSAGING_CONSENT_VERSION,
        agreementCurrent,
        needsReview: !hasAccess || !agreementCurrent || relationshipNeedsConfirmation || messagingNeedsPrompt,
        agentId: row.agent_id,
        agentName: row.agent_name,
        agencyName: row.agency_name,
        canMessage:
          row.relationship_status === "confirmed_client" &&
          row.messaging_consent_status === "granted" &&
          row.messaging_consent_version === MESSAGING_CONSENT_VERSION,
        prospectConsents,
        prospectOptions,
      },
    });
  } catch (err) {
    console.error("get_account_access error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
