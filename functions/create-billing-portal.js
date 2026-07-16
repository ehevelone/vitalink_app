const Stripe = require("stripe");
const { Pool } = require("pg");
const { getRsmPriceId } = require("./services/stripe-prices");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";
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
    ADD COLUMN IF NOT EXISTS current_period_end TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS billing_mode TEXT DEFAULT 'office_paid',
    ADD COLUMN IF NOT EXISTS billing_interval TEXT DEFAULT 'monthly',
    ADD COLUMN IF NOT EXISTS pricing_tier TEXT DEFAULT 'founders'
  `);

  await client.query(`
    ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS linked_rsm_id UUID
  `);
}

function normalizeBillingMode(value) {
  return value === "agent_paid" ? "agent_paid" : "office_paid";
}

function normalizeBillingInterval(value) {
  return value === "annual" ? "annual" : "monthly";
}

function normalizePricingTier(value) {
  return value === "regular" ? "regular" : "founders";
}

async function countBillableSeats(client, rsmId, billingMode) {
  if (billingMode === "agent_paid") {
    return 1;
  }

  const result = await client.query(
    `
    SELECT COUNT(*)::INT AS count
    FROM agents
    WHERE rsm_id = $1
      AND active = TRUE
      AND linked_rsm_id IS DISTINCT FROM $1
    `,
    [rsmId]
  );

  return Number(result.rows[0]?.count || 0) + 1;
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
    const body = JSON.parse(event.body || "{}");
    const selectedBillingMode = normalizeBillingMode(body.billingMode);
    const selectedBillingInterval = normalizeBillingInterval(body.billingInterval);

    await ensureBillingColumns(client);

    const rsm = await client.query(
      `
      SELECT
        id,
        email,
        stripe_customer_id,
        stripe_subscription_id,
        stripe_subscription_item_id,
        billing_active,
        subscription_status,
        billing_mode,
        billing_interval,
        pricing_tier
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
    const billingMode = selectedBillingMode || normalizeBillingMode(rsmData.billing_mode);
    const billingInterval = selectedBillingInterval || normalizeBillingInterval(rsmData.billing_interval);
    const pricingTier = normalizePricingTier(rsmData.pricing_tier);
    const rsmPriceId = getRsmPriceId({ pricingTier, billingInterval });

    if (!rsmPriceId) {
      return reply(500, {
        success: false,
        error: `Stripe ${pricingTier} RSM ${billingInterval} price is not configured`
      });
    }

    const checkoutQuantity = await countBillableSeats(client, rsmData.id, billingMode);

    const hasActiveSubscription =
      rsmData.billing_active === true &&
      rsmData.stripe_customer_id &&
      rsmData.stripe_subscription_id &&
      rsmData.stripe_subscription_item_id &&
      rsmData.subscription_status !== "canceled";

    if (hasActiveSubscription) {
      await client.query(
        "UPDATE rsms SET billing_mode = $1 WHERE id = $2",
        [billingMode, rsmData.id]
      );

      await stripe.subscriptionItems.update(
        rsmData.stripe_subscription_item_id,
        { quantity: checkoutQuantity }
      );

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

    await client.query(
      "UPDATE rsms SET billing_mode = $1, billing_interval = $2 WHERE id = $3",
      [billingMode, billingInterval, rsmData.id]
    );

    const checkoutParams = {
      mode: "subscription",
      line_items: [
        {
          price: rsmPriceId,
          quantity: checkoutQuantity
        }
      ],
      success_url: `${SITE}/core-node/rsm_report.html?billing=success`,
      cancel_url: `${SITE}/core-node/rsm_report.html?billing=cancel`,
      client_reference_id: String(rsmData.id),
      metadata: {
        rsm_id: String(rsmData.id),
        type: "rsm_agent_billing",
        billing_mode: billingMode,
        billing_interval: billingInterval,
        pricing_tier: pricingTier
      },
      subscription_data: {
        metadata: {
          rsm_id: String(rsmData.id),
          type: "rsm_agent_billing",
          billing_mode: billingMode,
          billing_interval: billingInterval,
          pricing_tier: pricingTier
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
      billing_mode: billingMode,
      billing_interval: billingInterval,
      pricing_tier: pricingTier,
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
