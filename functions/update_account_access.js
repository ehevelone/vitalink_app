const db = require("./services/db");
const { verifyUserSession } = require("./services/user-auth");
const {
  AGREEMENT_VERSION,
  MESSAGING_CONSENT_VERSION,
  ensureAccountAccessSchema,
  recordConsentEvent,
  setProspectConsent,
} = require("./services/account-access");
const {
  checkAccessCodeLimit,
  clearAccessCodeFailures,
  rateLimitScope,
  recordAccessCodeFailure,
} = require("./services/access-code-rate-limit");
const { createMailer, fromAddress } = require("./services/mailer");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });

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
    const current = await db.query(
      `SELECT u.agent_id, u.purchase_code, u.email, u.relationship_status,
              a.name AS agent_name
       FROM users u
       LEFT JOIN agents a ON a.id=u.agent_id
       WHERE u.id=$1 LIMIT 1`,
      [userId]
    );
    if (!current.rows.length) return reply(404, { success: false, error: "Account not found" });
    const agentId = current.rows[0].agent_id;
    const action = String(body.action || "");

    if (action === "confirm") {
      if (body.userAttestation !== true || body.agreementAccepted !== true) {
        return reply(400, { success: false, error: "The client/user must accept the agreement." });
      }

      const relationship = !agentId
        ? "not_applicable"
        : body.relationship === "prospect"
          ? "confirmed_prospect"
          : "confirmed_client";
      const consent = !agentId || relationship === "confirmed_prospect"
        ? "not_applicable"
        : body.messagingConsent === true
          ? "granted"
          : "deferred";

      await db.query(
        `UPDATE users
         SET relationship_status=$1,
             relationship_confirmed_at=NOW(),
             relationship_review_requested_at=NULL,
             user_agreement_version=$2,
             user_agreement_accepted_at=NOW(),
             messaging_consent_status=$3,
             messaging_consent_version=$4,
             messaging_consented_at=CASE WHEN $3='granted' THEN NOW() ELSE NULL END,
             messaging_withdrawn_at=CASE WHEN $3='granted' THEN NULL ELSE messaging_withdrawn_at END,
             access_prompted_at=CASE WHEN $3='deferred' THEN NOW() ELSE access_prompted_at END,
             access_prompt_count=CASE WHEN $3='deferred' THEN access_prompt_count+1 ELSE access_prompt_count END
         WHERE id=$5`,
        [relationship, AGREEMENT_VERSION, consent, MESSAGING_CONSENT_VERSION, userId]
      );
      await recordConsentEvent({
        userId, agentId, eventType: "relationship_confirmed", eventValue: relationship,
        platform: body.platform, deviceId: body.deviceId,
      });
      await recordConsentEvent({
        userId, agentId, eventType: "messaging_consent", eventValue: consent,
        platform: body.platform, deviceId: body.deviceId,
      });
      if (relationship === "confirmed_prospect") {
        const selections = body.prospectConsents && typeof body.prospectConsents === "object"
          ? body.prospectConsents
          : {};
        for (const category of ["medicare", "life"]) {
          await setProspectConsent({
            userId,
            agentId,
            agentName: current.rows[0].agent_name,
            category,
            granted: selections[category] === true,
            platform: body.platform,
            deviceId: body.deviceId,
          });
        }
      }
      return reply(200, { success: true });
    }

    if (action === "not_now") {
      await db.query(
        `UPDATE users SET access_prompted_at=NOW(), access_prompt_count=access_prompt_count+1 WHERE id=$1`,
        [userId]
      );
      await recordConsentEvent({ userId, agentId, eventType: "confirmation_deferred", platform: body.platform, deviceId: body.deviceId });
      return reply(200, { success: true });
    }

    if (action === "review_requested") {
      await db.query(
        `UPDATE users
         SET relationship_status='review_requested', relationship_review_requested_at=NOW(),
             messaging_consent_status='paused', messaging_withdrawn_at=NOW()
         WHERE id=$1`,
        [userId]
      );
      await recordConsentEvent({ userId, agentId, eventType: "relationship_review_requested", platform: body.platform, deviceId: body.deviceId });
      return reply(200, { success: true });
    }

    if (action === "policy_verified") {
      if (body.documentMatch !== true || !agentId) {
        return reply(400, { success: false, error: "Policy verification did not match the connected agent." });
      }
      const matchType = body.matchType === "agency" ? "agency" : "agent";
      if (matchType === "agency") {
        await db.query(
          `INSERT INTO policy_relationship_reviews (user_id, agent_id, match_type)
           VALUES ($1,$2,'agency')`,
          [userId, agentId]
        );
        await recordConsentEvent({
          userId, agentId, eventType: "policy_agency_match_review_requested", eventValue: "agency",
          platform: body.platform, deviceId: body.deviceId,
        });
        return reply(200, { success: true, reviewRequired: true });
      }
      await db.query(
        `UPDATE users SET relationship_status='pending_policy_confirmation',
           messaging_consent_status='pending'
         WHERE id=$1`,
        [userId]
      );
      await recordConsentEvent({
        userId, agentId, eventType: "policy_agent_match", eventValue: body.matchType || "agent",
        platform: body.platform, deviceId: body.deviceId,
      });
      return reply(200, { success: true });
    }

    if (action === "messaging_consent") {
      if (!agentId || body.userAttestation !== true) {
        return reply(400, { success: false, error: "The client/user must make this choice." });
      }
      const consent = body.messagingConsent === true ? "granted" : "withdrawn";
      if (consent === "granted") {
        const relationship = await db.query(
          "SELECT relationship_status FROM users WHERE id=$1 LIMIT 1",
          [userId]
        );
        if (relationship.rows[0]?.relationship_status !== "confirmed_client") {
          return reply(400, { success: false, error: "Messaging is available only to confirmed clients." });
        }
      }
      await db.query(
        `UPDATE users SET messaging_consent_status=$1,
           messaging_consent_version=$2,
           messaging_consented_at=CASE WHEN $1='granted' THEN NOW() ELSE messaging_consented_at END,
           messaging_withdrawn_at=CASE WHEN $1='withdrawn' THEN NOW() ELSE NULL END
         WHERE id=$3`,
        [consent, MESSAGING_CONSENT_VERSION, userId]
      );
      await recordConsentEvent({
        userId, agentId, eventType: "messaging_consent", eventValue: consent,
        platform: body.platform, deviceId: body.deviceId,
      });
      return reply(200, { success: true, messagingConsentStatus: consent });
    }

    if (action === "prospect_marketing_consent") {
      if (!agentId || body.userAttestation !== true) {
        return reply(400, { success: false, error: "The user must make this choice." });
      }
      if (current.rows[0].relationship_status !== "confirmed_prospect") {
        return reply(400, { success: false, error: "Prospect messaging is available only to confirmed prospects." });
      }
      const category = String(body.category || "").toLowerCase();
      if (!["medicare", "life"].includes(category)) {
        return reply(400, { success: false, error: "Unsupported message category." });
      }
      const granted = body.granted === true;
      await setProspectConsent({
        userId,
        agentId,
        agentName: current.rows[0].agent_name,
        category,
        granted,
        declinedStatus: granted ? null : "withdrawn",
        platform: body.platform,
        deviceId: body.deviceId,
      });
      if (!granted) {
        await db.query(
          `UPDATE prospect_marketing_consents
           SET status='withdrawn', withdrawn_at=NOW(), expires_at=NULL, updated_at=NOW()
           WHERE user_id=$1 AND agent_id=$2 AND category=$3`,
          [userId, agentId, category]
        );
        await db.query(
          `UPDATE prospect_marketing_deliveries
           SET status='cancelled'
           WHERE user_id=$1 AND agent_id=$2 AND category=$3 AND status='queued'`,
          [userId, agentId, category]
        ).catch(() => {});
      }
      return reply(200, { success: true, category, status: granted ? "granted" : "withdrawn" });
    }

    if (action === "disconnect") {
      const sponsor = current.rows[0].purchase_code ? "personal" : "locked";
      await db.query(
        `UPDATE users
         SET agent_id=NULL, access_sponsor=$1, relationship_status='disconnected',
             messaging_consent_status='withdrawn', messaging_withdrawn_at=NOW()
         WHERE id=$2`,
        [sponsor, userId]
      );
      if (agentId) {
        await db.query(
          `UPDATE prospect_marketing_consents
           SET status='withdrawn', withdrawn_at=NOW(), expires_at=NULL, updated_at=NOW()
           WHERE user_id=$1 AND agent_id=$2`,
          [userId, agentId]
        );
      }
      await recordConsentEvent({ userId, agentId, eventType: "agent_disconnected", eventValue: sponsor, platform: body.platform, deviceId: body.deviceId });
      try {
        await createMailer().sendMail({
          from: fromAddress("VitaLink"),
          to: current.rows[0].email,
          subject: "Your VitaLink agent connection has ended",
          text: "Your agent connection has ended. You can enter another agent's code or an access code in the app.",
        });
        await recordConsentEvent({
          userId,
          agentId,
          eventType: "agent_disconnect_email_sent",
          eventValue: sponsor,
          platform: body.platform,
          deviceId: body.deviceId,
        });
      } catch (mailError) {
        console.error("disconnect email error:", mailError);
        await recordConsentEvent({
          userId,
          agentId,
          eventType: "agent_disconnect_email_failed",
          eventValue: sponsor,
          platform: body.platform,
          deviceId: body.deviceId,
        });
      }
      return reply(200, { success: true, sponsor });
    }

    if (action === "connect_code") {
      const scope = rateLimitScope("account-access-code", userId);
      const limit = await checkAccessCodeLimit(scope);
      if (!limit.allowed) {
        return reply(429, {
          success: false,
          error: "Too many incorrect codes. Try again in 15 minutes.",
          retryAfterSeconds: limit.retryAfterSeconds,
        });
      }
      const code = String(body.code || "")
        .replace(/[\u2010-\u2015\u2212]/g, "-")
        .replace(/[^A-Za-z0-9-]/g, "")
        .trim()
        .toUpperCase();
      if (!code) return reply(400, { success: false, error: "Enter an access code" });

      const agent = await db.query(
        "SELECT id FROM agents WHERE unlock_code=$1 AND active=true LIMIT 1",
        [code]
      );
      if (agent.rows.length) {
        await db.query(
          `UPDATE users SET agent_id=$1, access_sponsor='agent',
             relationship_status='pending_confirmation',
             messaging_consent_status='pending', messaging_consent_version=NULL,
             messaging_consented_at=NULL, messaging_withdrawn_at=NOW()
           WHERE id=$2`,
          [agent.rows[0].id, userId]
        );
        await recordConsentEvent({ userId, agentId: agent.rows[0].id, eventType: "agent_connected", platform: body.platform, deviceId: body.deviceId });
        await clearAccessCodeFailures(scope);
        return reply(200, { success: true, sponsor: "agent" });
      }

      await db.query(`ALTER TABLE activation_codes ADD COLUMN IF NOT EXISTS redeemed BOOLEAN NOT NULL DEFAULT FALSE, ADD COLUMN IF NOT EXISTS redeemed_at TIMESTAMPTZ, ADD COLUMN IF NOT EXISTS redeemed_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL`);
      const personal = await db.query(
        "SELECT code, redeemed, redeemed_user_id FROM activation_codes WHERE code=$1 LIMIT 1",
        [code]
      );
      const owned = current.rows[0].purchase_code === code ||
        Number(personal.rows[0]?.redeemed_user_id) === Number(userId);
      if (!personal.rows.length || (personal.rows[0].redeemed === true && !owned)) {
        const failure = await recordAccessCodeFailure(scope, code);
        if (failure.locked) {
          return reply(429, {
            success: false,
            error: "Too many incorrect codes. Try again in 15 minutes.",
            retryAfterSeconds: 15 * 60,
          });
        }
        return reply(404, { success: false, error: "That access code is not valid" });
      }
      await db.query("UPDATE activation_codes SET redeemed=true, redeemed_at=COALESCE(redeemed_at,NOW()), redeemed_user_id=$2 WHERE code=$1", [code, userId]);
      await db.query(
        `UPDATE users SET purchase_code=$1, agent_id=NULL, access_sponsor='personal',
           relationship_status='not_applicable', messaging_consent_status='not_applicable',
           messaging_consent_version=NULL, messaging_consented_at=NULL,
           messaging_withdrawn_at=NOW()
         WHERE id=$2`,
        [code, userId]
      );
      await recordConsentEvent({ userId, agentId, eventType: "personal_access_connected", platform: body.platform, deviceId: body.deviceId });
      await clearAccessCodeFailures(scope);
      return reply(200, { success: true, sponsor: "personal" });
    }

    return reply(400, { success: false, error: "Unknown action" });
  } catch (err) {
    console.error("update_account_access error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
