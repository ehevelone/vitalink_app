const Stripe = require("stripe");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

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
          price: process.env.STRIPE_AGENT_PRICE_ID,
          quantity: 1
        }
      ],

      // 🔥 helps Stripe + receipts
      customer_email: email || undefined,

      // 🔥 CRITICAL FOR WEBHOOK MATCHING
      metadata: {
        agentId: String(agentId),
        type: "agent_subscription"
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