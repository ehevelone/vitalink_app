const Stripe = require("stripe");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

function getPlan(body = {}) {
  const plan =
    (body.plan || body.product || body.subscription || "")
      .toString()
      .trim()
      .toLowerCase();

  if (["app_crm", "app-crm", "combo", "appcrm"].includes(plan)) {
    return {
      priceId:
        process.env.STRIPE_FOUNDERS_APP_CRM_PRICE_ID ||
        process.env.STRIPE_APP_CRM_PRICE_ID,
      type: "app_crm_subscription"
    };
  }

  return {
    priceId:
      process.env.STRIPE_FOUNDERS_AGENT_PRICE_ID ||
      process.env.STRIPE_AGENT_PRICE_ID,
    type: "agent_subscription"
  };
}

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: corsHeaders,
      body: ""
    };
  }

  try {

    // 🔥 ADD BODY (needed for agent linkage)
    let body = {};
    try {
      body = JSON.parse(event.body || "{}");
    } catch (_) {}

    const agentId = body.agentId || "";
    const email = body.email || "";
    const plan = getPlan(body);

    if (!plan.priceId) {
      return {
        statusCode: 500,
        headers: corsHeaders,
        body: JSON.stringify({ error: "Stripe price is not configured" })
      };
    }

    const session = await stripe.checkout.sessions.create({

      // 🔥 ACH FIRST
      payment_method_types: ["us_bank_account", "card"],

      // 🔥 SMOOTH ACH FLOW
      payment_method_options: {
        us_bank_account: {
          verification_method: "automatic"
        }
      },

      mode: "subscription",

      line_items: [
        {
          price: plan.priceId,
          quantity: 1
        }
      ],

      // 🔥 helps Stripe + receipts
      customer_email: email || undefined,

      // 🔥 CRITICAL FOR WEBHOOK MATCHING
      metadata: {
        agentId: String(agentId),
        type: plan.type
      },

      subscription_data: {
        metadata: {
          agentId: String(agentId),
          type: plan.type
        }
      },

      success_url:
        "https://myvitalink.app/agent-success.html?session_id={CHECKOUT_SESSION_ID}",

      cancel_url:
        "https://myvitalink.app/activate.html"

    });

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ url: session.url })
    };

  } catch (err) {

    console.error("Stripe agent checkout error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: err.message })
    };

  }

};
