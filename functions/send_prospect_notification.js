const crypto = require("crypto");
const admin = require("firebase-admin");
const db = require("./services/db");
const { verifyAgentSession } = require("./services/agent-auth");
const { ensureAccountAccessSchema, PROSPECT_CONSENT_VERSION } = require("./services/account-access");
const {
  MAX_SENDS_PER_30_DAYS,
  TEMPLATES,
  ensureProspectMarketingSchema,
  marketingEnabled,
} = require("./services/prospect-marketing");
const {
  deviceLanguage,
  ensureLanguageColumns,
  notificationText,
} = require("./services/notification-language");

const reply = (statusCode, body) => ({
  statusCode,
  headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  body: JSON.stringify(body),
});

function initFirebase() {
  if (admin.apps.length) return;
  let privateKey = process.env.FIREBASE_PRIVATE_KEY || "";
  if (privateKey.includes("\\n")) privateKey = privateKey.replace(/\\n/g, "\n");
  admin.initializeApp({ credential: admin.credential.cert({
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey,
  }) });
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    const body = JSON.parse(event.body || "{}");
    const agent = await verifyAgentSession({
      agentEmail: String(body.agentEmail || "").trim(),
      token: body.agentSessionToken,
    });
    if (!agent) return reply(403, { success: false, error: "Unauthorized" });

    const templateId = String(body.templateId || "");
    const template = TEMPLATES[templateId];
    if (!template) return reply(400, { success: false, error: "Choose an approved message." });
    if (!marketingEnabled(template.category)) {
      return reply(403, { success: false, error: "Prospect messages are currently paused." });
    }

    await ensureAccountAccessSchema();
    await ensureLanguageColumns();
    await ensureProspectMarketingSchema();
    initFirebase();

    const eligible = await db.query(
      `SELECT u.id AS user_id, ud.id AS device_row_id, ud.device_token, ud.app_language
       FROM users u
       JOIN prospect_marketing_consents c
         ON c.user_id=u.id AND c.agent_id=u.agent_id
       JOIN user_devices ud ON ud.user_id=u.id
       WHERE u.agent_id=$1
         AND u.relationship_status='confirmed_prospect'
         AND c.category=$2
         AND c.status='granted'
         AND c.consent_version=$3
         AND c.expires_at > NOW()
         AND ud.device_status='active'
         AND ud.device_token IS NOT NULL
         AND TRIM(ud.device_token) NOT IN ('', 'NO_TOKEN')
         AND (SELECT COUNT(*) FROM prospect_marketing_deliveries d
              WHERE d.user_id=u.id AND d.agent_id=$1 AND d.category=$2
                AND d.status='sent' AND d.sent_at >= NOW() - INTERVAL '30 days') < $4`,
      [agent.id, template.category, PROSPECT_CONSENT_VERSION, MAX_SENDS_PER_30_DAYS]
    );

    const recipients = new Map();
    for (const row of eligible.rows) {
      const token = String(row.device_token || "").trim();
      if (token && !recipients.has(String(row.user_id))) {
        recipients.set(String(row.user_id), { ...row, token });
      }
    }

    let successCount = 0;
    let failureCount = 0;
    for (const row of recipients.values()) {
      // The message is shown in the prospect's own app language.
      const language = deviceLanguage(row);
      const agentName = agent.name || (language === "es" ? "su agente" : "Your Agent");
      const messageText = language === "es" ? template.textEs(agentName) : template.text(agentName);
      const title = notificationText("messageFrom", language, { name: agent.name });
      const deliveryId = crypto.randomUUID();
      await db.query(
        `INSERT INTO prospect_marketing_deliveries
          (id,user_id,agent_id,category,template_id,status)
         VALUES ($1,$2,$3,$4,$5,'queued')`,
        [deliveryId, row.user_id, agent.id, template.category, templateId]
      );
      try {
        await admin.messaging().send({
          token: row.token,
          notification: { title, body: messageText },
          android: { priority: "high", notification: { channelId: "vitalink_high_importance" } },
          data: {
            click_action: "FLUTTER_NOTIFICATION_CLICK",
            route: "/prospect_contact_request",
            type: "prospect_marketing",
            deliveryId,
            category: template.category,
            templateId,
            topic: template.topic,
            agentName,
            title,
            body: messageText,
          },
        });
        await db.query("UPDATE prospect_marketing_deliveries SET status='sent', sent_at=NOW() WHERE id=$1", [deliveryId]);
        successCount += 1;
      } catch (_) {
        await db.query("UPDATE prospect_marketing_deliveries SET status='failed' WHERE id=$1", [deliveryId]);
        failureCount += 1;
      }
    }

    return reply(200, {
      success: true,
      category: template.category,
      templateId,
      devicesTargeted: recipients.size,
      successCount,
      failureCount,
    });
  } catch (error) {
    console.error("send_prospect_notification error", error?.message);
    return reply(500, { success: false, error: "Unable to send prospect message." });
  }
};
