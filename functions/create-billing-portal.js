const Stripe = require("stripe");
const { Pool } = require("pg");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";
const RSM_PRICE_ID =
  process.env.STRIPE_FOUNDERS_RSM_PRICE_ID ||
  process.env.STRIPE_RSM_PRICE_ID;

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
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

async function ensureBillingColumns(client) {
  await client.query(`
    ALTER TABLE rsms
    ADD COLUMN IF NOT EXISTS billing_active BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT,
    ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT,
    ADD COLUMN IF NOT EXISTS stripe_subscription_item_id TEXT,
    ADD COLUMN IF NOT EXISTS subscription_status TEXT,
    ADD COLUMN IF NOT EXISTS current_period_end TIMESTAMPTZ
  `);
}

async function countActiveAgents(client, rsmId) {
  const result = await client.query(
    `
    SELECT COUNT(*)::INT AS count
    FROM agents
    WHERE rsm_id = $1
      AND active = TRUE
    `,
    [rsmId]
  );

  return Number(result.rows[0]?.count || 0);
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  const sessionToken = event.headers["x-admin-session"];

  if (!sessionToken) {
    return reply(401, { success: false, error: "Unauthorized" });
  }

  const client = await pool.connect();

  try {
    await ensureBillingColumns(client);

    if (!RSM_PRICE_ID) {
      return reply(500, {
        success: false,
        error: "Stripe RSM price is not configured"
      });
    }

    const rsm = await client.query(
      `
      SELECT
        id,
        email,
        stripe_customer_id,
        stripe_subscription_id,
        stripe_subscription_item_id,
        billing_active,
        subscription_status
      FROM rsms
      WHERE admin_session_token = $1
        AND role = 'rsm'
        AND admin_session_expires > NOW()
      LIMIT 1
      `,
      [sessionToken]
    );

    if (!rsm.rows.length) {
      return reply(401, { success: false, error: "Invalid session" });
    }

    const rsmData = rsm.rows[0];
    const activeAgents = await countActiveAgents(client, rsmData.id);
    const checkoutQuantity = Math.max(activeAgents, 1);
    const hasActiveSubscription =
      rsmData.billing_active === true &&
      rsmData.stripe_customer_id &&
      rsmData.stripe_subscription_id &&
      rsmData.stripe_subscription_item_id &&
      rsmData.subscription_status !== "canceled";

    if (hasActiveSubscription) {
      const portalSession = await stripe.billingPortal.sessions.create({
        customer: rsmData.stripe_customer_id,
        return_url: `${SITE}/core-node/rsm_report.html`
      });

      return reply(200, {
        success: true,
        mode: "portal",
        url: portalSession.url
      });
    }

    const checkoutParams = {
      mode: "subscription",
      line_items: [
        {
          price: RSM_PRICE_ID,
          quantity: checkoutQuantity
        }
      ],
      success_url: `${SITE}/core-node/rsm_report.html?billing=success`,
      cancel_url: `${SITE}/core-node/rsm_report.html?billing=cancel`,
      client_reference_id: String(rsmData.id),
      metadata: {
        rsm_id: String(rsmData.id),
        type: "rsm_agent_billing"
      },
      subscription_data: {
        metadata: {
          rsm_id: String(rsmData.id),
          type: "rsm_agent_billing"
        }
      }
    };

    if (rsmData.stripe_customer_id) {
      checkoutParams.customer = rsmData.stripe_customer_id;
    } else {
      checkoutParams.customer_email = rsmData.email;
    }

    const checkoutSession =
      await stripe.checkout.sessions.create(checkoutParams);

    return reply(200, {
      success: true,
      mode: "checkout",
      active_agents: activeAgents,
      billed_quantity: checkoutQuantity,
      url: checkoutSession.url
    });

  } catch (err) {
    console.error("Billing portal error:", err);

    return reply(500, {
      success: false,
      error: err.message
    });

  } finally {
    client.release();
  }
};
