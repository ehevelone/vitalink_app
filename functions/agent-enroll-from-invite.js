// functions/agent-enroll-from-invite.js

const { Pool } = require("pg");
const { randomBytes } = require("crypto");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";

function generateAgentCode(prefix = "AGT", length = 8) {

  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  const bytes = randomBytes(length);
  for (let i = 0; i < length; i++) code += chars[bytes[i] % chars.length];

  return `${prefix}-${code}`;
}

exports.handler = async function (event) {

  /* INVITE LINK CLICK */
  if (event.httpMethod === "GET") {

    const rsmCode = event.queryStringParameters?.rsm;

    if (!rsmCode) {
      return {
        statusCode: 302,
        headers: { Location: `${SITE}` }
      };
    }

    const client = await pool.connect();

    try {

      /* VALIDATE RSM */

      const rsm = await client.query(
        `SELECT id, billing_active, billing_mode, pricing_tier, subscription_status,
                stripe_customer_id, stripe_subscription_id, stripe_subscription_item_id
         FROM rsms
         WHERE invite_code = $1
         AND role = 'rsm'
         AND active = true
         LIMIT 1`,
        [rsmCode]
      );

      if (rsm.rows.length === 0) {
        return {
          statusCode: 302,
          headers: { Location: `${SITE}` }
        };
      }

      const office = rsm.rows[0];
      const override = [office.subscription_status, office.stripe_customer_id,
        office.stripe_subscription_id, office.stripe_subscription_item_id]
        .some(value => String(value || "").toLowerCase() === "admin_override");
      if (office.billing_active !== true && !override) {
        return { statusCode: 302, headers: { Location: `${SITE}/agent-access` } };
      }

      const rsmId = office.id;
      const agentPaid = office.billing_mode === "agent_paid";

      await client.query(`ALTER TABLE agents
        ADD COLUMN IF NOT EXISTS pricing_tier TEXT DEFAULT 'founders'`);

      /* GENERATE AGENT CODE */

      const agentCode = generateAgentCode();

      /* CREATE AGENT RECORD */

      await client.query(
        `INSERT INTO agents
          (unlock_code, active, role, rsm_id, billing_owner,
           subscription_status, pricing_tier, created_at)
         VALUES
          ($1, false, 'agent', $2, $3, $4, $5, NOW())`,
        [
          agentCode,
          rsmId,
          agentPaid ? "agent" : "agency",
          agentPaid ? "pending_payment" : "active",
          office.pricing_tier === "regular" ? "regular" : "founders"
        ]
      );

      /* REDIRECT TO LANDING PAGE */

      return {
        statusCode: 302,
        headers: {
          Location: `${SITE}/core-node/agent_enrolled.html?code=${agentCode}`
        }
      };

    } catch (err) {

      console.error("agent-enroll-from-invite error:", err);

      return {
        statusCode: 302,
        headers: { Location: `${SITE}` }
      };

    } finally {

      client.release();

    }

  }

  /* BLOCK OTHER METHODS */

  return {
    statusCode: 405,
    body: "Method Not Allowed"
  };

};
