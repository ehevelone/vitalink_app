const crypto = require("crypto");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_DB_URL || process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false },
});
const SITE = "https://myvitalink.app";

function generateAgentCode(prefix = "AGT", length = 8) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  const bytes = crypto.randomBytes(length);
  return `${prefix}-${Array.from(bytes, (byte) => chars[byte % chars.length]).join("")}`;
}

function isAdminOverride(...values) {
  return values.some((value) => String(value || "").trim().toLowerCase() === "admin_override");
}

exports.handler = async function (event) {
  if (event.httpMethod !== "GET") return { statusCode: 405, body: "Method Not Allowed" };

  const rsmCode = String(event.queryStringParameters?.rsm || "").trim().toUpperCase();
  if (!rsmCode) return { statusCode: 302, headers: { Location: SITE } };

  const client = await pool.connect();
  try {
    const result = await client.query(
      `SELECT id,billing_active,billing_mode,pricing_tier,subscription_status,
              stripe_customer_id,stripe_subscription_id,stripe_subscription_item_id
       FROM rsms WHERE invite_code=$1 AND role='rsm' AND active=TRUE LIMIT 1`,
      [rsmCode]
    );
    if (result.rows.length === 0) return { statusCode: 302, headers: { Location: SITE } };

    const rsm = result.rows[0];
    const override = isAdminOverride(rsm.subscription_status, rsm.stripe_customer_id,
      rsm.stripe_subscription_id, rsm.stripe_subscription_item_id);
    if (rsm.billing_active !== true && !override) {
      return { statusCode: 302, headers: { Location: `${SITE}/core-node/rsm.html?billing=required` } };
    }

    const billingOwner = rsm.billing_mode === "agent_paid" ? "agent" : "agency";
    const subscriptionStatus = billingOwner === "agent" ? "pending_payment" : "active";
    const pricingTier = rsm.pricing_tier === "regular" ? "regular" : "founders";
    const agentCode = generateAgentCode();
    await client.query(
      `INSERT INTO agents
         (unlock_code,active,role,rsm_id,billing_owner,subscription_status,pricing_tier,created_at)
       VALUES ($1,FALSE,'agent',$2,$3,$4,$5,NOW())`,
      [agentCode, rsm.id, billingOwner, subscriptionStatus, pricingTier]
    );
    return { statusCode: 302, headers: {
      Location: `${SITE}/core-node/agent_enrolled.html?code=${agentCode}`,
    } };
  } catch (err) {
    console.error("agent-enroll-from-invite error:", err);
    return { statusCode: 302, headers: { Location: SITE } };
  } finally {
    client.release();
  }
};
