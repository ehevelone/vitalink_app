const crypto = require("crypto");
const db = require("./services/db");
const {
  clean,
  ensureReferralSchema,
  reply,
  verifyUserSession,
} = require("./services/referral-center");

const VALID_RELATIONSHIPS = new Set([
  "Spouse",
  "Parent",
  "Child",
  "Grandparent",
  "Friend",
  "Coworker",
  "Neighbor",
  "Caregiver",
  "Adult Child",
  "Other",
]);

const VALID_REASONS = new Set([
  "Turning 65",
  "Medicare Questions",
  "Insurance Review",
  "Multiple Medications",
  "Caregiver Needs",
  "Recently Retired",
  "Wants Better Organization",
  "Emergency Preparedness",
  "Family Member Concern",
  "Other",
]);

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureReferralSchema();

    const body = JSON.parse(event.body || "{}");
    const userId = clean(body.userId || body.user_id);
    const sessionToken = clean(body.sessionToken);
    const user = await verifyUserSession(userId, sessionToken);

    if (!user) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    if (!user.agent_id) {
      return reply(400, {
        success: false,
        error: "No connected agent found for this VitaLink account.",
      });
    }

    const referralName = clean(body.referralName || body.referral_name);
    const referralPhone = clean(body.phone || body.referralPhone);
    const referralEmail = clean(body.email || body.referralEmail).toLowerCase();
    const relationship = clean(body.relationship);
    const reason = clean(body.reason);
    const notes = clean(body.notes);
    const source = clean(body.source) || "recommend_my_agent";

    if (!referralName) {
      return reply(400, { success: false, error: "Referral name is required." });
    }

    if (!referralPhone && !referralEmail) {
      return reply(400, {
        success: false,
        error: "Enter a phone number or email for the referral.",
      });
    }

    if (relationship && !VALID_RELATIONSHIPS.has(relationship)) {
      return reply(400, { success: false, error: "Invalid relationship." });
    }

    if (reason && !VALID_REASONS.has(reason)) {
      return reply(400, { success: false, error: "Invalid referral reason." });
    }

    const agentRes = await db.query(
      `SELECT id, name, email, phone FROM agents WHERE id = $1 LIMIT 1`,
      [user.agent_id]
    );

    if (!agentRes.rows.length) {
      return reply(404, { success: false, error: "Connected agent not found." });
    }

    const publicToken = crypto.randomBytes(24).toString("hex");
    const siteUrl = (process.env.PUBLIC_SITE_URL || "https://myvitalink.app").replace(/\/$/, "");
    const referralLink = `${siteUrl}/referral.html?r=${publicToken}`;

    const insert = await db.query(
      `
      INSERT INTO agent_referrals (
        id,
        agent_id,
        referring_user_id,
        referral_name,
        referral_phone,
        referral_email,
        relationship,
        reason,
        notes,
        source,
        public_token,
        status
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'Introduction Sent')
      RETURNING *
      `,
      [
        crypto.randomUUID(),
        user.agent_id,
        user.id,
        referralName,
        referralPhone || null,
        referralEmail || null,
        relationship || null,
        reason || null,
        notes || null,
        source,
        publicToken,
      ]
    );

    const referral = insert.rows[0];
    const referringClient = `${user.first_name || ""} ${user.last_name || ""}`.trim() ||
      user.email;

    return reply(200, {
      success: true,
      referral,
      referralLink,
      referringClient,
      agentName: agentRes.rows[0].name || "my insurance agent",
    });
  } catch (err) {
    console.error("submit_agent_referral error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
