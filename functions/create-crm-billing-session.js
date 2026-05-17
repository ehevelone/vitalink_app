const Stripe = require("stripe");
const db = require("./services/db");
const { verifyAgentSession } = require("./services/agent-auth");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const SITE = "https://myvitalink.app";
const CRM_PRICE_ID =
  process.env.STRIPE_FOUNDERS_CRM_PRICE_ID ||
  process.env.STRIPE_CRM_PRICE_ID;

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type, x-agent-session",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json"
};

function reply(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify(body)
  };
}

async function ensureCrmBillingColumns() {
  await db.query(`
    ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS crm_subscription_status TEXT,
    ADD COLUMN IF NOT EXISTS crm_subscription_valid BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS crm_stripe_customer_id TEXT,
    ADD COLUMN IF NOT EXISTS crm_stripe_subscription_id TEXT
  `);
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  let body = {};

  try {
    body = JSON.parse(event.body || "{}");
  } catch {
    return reply(400, { success: false, error: "Invalid request body" });
  }

  const token =
    event.headers["x-agent-session"] ||
    body.agentSessionToken;

  const agentId = body.agentId;

  const sessionAgent = await verifyAgentSession({
    agentId,
    token
  });

  if (!sessionAgent) {
    return reply(403, { success: false, error: "Unauthorized" });
  }

  try {
    await ensureCrmBillingColumns();

    if (!CRM_PRICE_ID) {
      return reply(500, {
        success: false,
        error: "Stripe CRM price is not configured"
      });
    }

    const agentRes = await db.query(
      `
      SELECT
        id,
        email,
        crm_stripe_customer_id,
        crm_stripe_subscription_id,
        crm_subscription_status,
        crm_subscription_valid
      FROM agents
      WHERE id = $1
      LIMIT 1
      `,
      [sessionAgent.id]
    );

    if (!agentRes.rows.length) {
      return reply(404, { success: false, error: "Agent not found" });
    }

    const agent = agentRes.rows[0];
    const crmActive =
      agent.crm_subscription_valid === true &&
      ["active", "trialing"].includes(agent.crm_subscription_status);

    if (
      crmActive &&
      agent.crm_stripe_customer_id &&
      agent.crm_stripe_subscription_id
    ) {
      const portalSession =
        await stripe.billingPortal.sessions.create({
          customer: agent.crm_stripe_customer_id,
          return_url: `${SITE}/crm/login.html`
        });

      return reply(200, {
        success: true,
        mode: "portal",
        crm_active: crmActive,
        url: portalSession.url
      });
    }

    const checkoutParams = {
      mode: "subscription",
      payment_method_types: ["us_bank_account", "card"],
      payment_method_options: {
        us_bank_account: {
          verification_method: "automatic"
        }
      },
      line_items: [
        {
          price: CRM_PRICE_ID,
          quantity: 1
        }
      ],
      customer_email: agent.email || undefined,
      client_reference_id: String(agent.id),
      metadata: {
        type: "crm_subscription",
        agentId: String(agent.id)
      },
      subscription_data: {
        metadata: {
          type: "crm_subscription",
          agentId: String(agent.id)
        }
      },
      success_url: `${SITE}/crm/login.html?crm_billing=success`,
      cancel_url: `${SITE}/crm/login.html?crm_billing=cancel`
    };

    const checkoutSession =
      await stripe.checkout.sessions.create(checkoutParams);

    return reply(200, {
      success: true,
      mode: "checkout",
      crm_active: false,
      url: checkoutSession.url
    });

  } catch (err) {
    console.error("create-crm-billing-session error:", err);

    return reply(500, {
      success: false,
      error: err.message
    });
  }
};
