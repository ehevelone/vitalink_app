const Stripe = require("stripe");
const crypto = require("crypto");
const { Pool } = require("pg");
const { getActivationPriceId } = require("./services/stripe-prices");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

function generateCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

  const part = (len) => {
    const bytes = crypto.randomBytes(len);
    return Array.from(bytes, (byte) => chars[byte % chars.length]).join("");
  };

  return `VL-${part(4)}-${part(4)}`;
}

function getPaymentIntentId(value) {
  if (!value) return null;
  return typeof value === "string" ? value : value.id;
}

exports.handler = async (event) => {

  const sig =
    event.headers["stripe-signature"] ||
    event.headers["Stripe-Signature"];

  let stripeEvent;

  try {

    stripeEvent = stripe.webhooks.constructEvent(
      event.body,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET
    );

    console.log("Stripe event type:", stripeEvent.type);

  } catch (err) {

    console.error("Webhook verification failed:", err);

    return {
      statusCode: 400,
      body: `Webhook Error: ${err.message}`,
    };

  }

  if (stripeEvent.type !== "checkout.session.completed") {
    console.log("Ignored Stripe event:", stripeEvent.type);
    return {
      statusCode: 200,
      body: JSON.stringify({ received: true, ignored: true })
    };
  }

  try {
    const eventSession = stripeEvent.data.object;
    const session = await stripe.checkout.sessions.retrieve(eventSession.id, {
      expand: ["line_items.data.price"]
    });

    const lineItems = session.line_items?.data || [];
    const expectedPriceId = getActivationPriceId();
    const validLineItem = lineItems.length === 1 &&
      lineItems[0].price?.id === expectedPriceId &&
      lineItems[0].quantity === 1;

    if (
      session.mode !== "payment" ||
      session.payment_status !== "paid" ||
      session.metadata?.purchase_type !== "consumer_activation" ||
      session.currency !== "usd" ||
      session.amount_total !== 4995 ||
      !validLineItem
    ) {
      console.error("Rejected activation Checkout Session", {
        sessionId: session.id,
        mode: session.mode,
        paymentStatus: session.payment_status,
        purchaseType: session.metadata?.purchase_type,
        currency: session.currency,
        amountTotal: session.amount_total
      });
      return {
        statusCode: 200,
        body: JSON.stringify({ received: true, ignored: true })
      };
    }

    const name = session.customer_details?.individual_name ||
      session.customer_details?.name || null;
    const email = String(session.customer_details?.email || "")
      .trim()
      .toLowerCase();

    if (!name || !email) {
      throw new Error(`Paid Checkout Session ${session.id} is missing purchaser identity`);
    }

    const paymentIntentId = getPaymentIntentId(session.payment_intent);
    const paidAt = new Date(stripeEvent.created * 1000);
    const client = await pool.connect();

    try {
      for (let attempt = 0; attempt < 5; attempt += 1) {
        const code = generateCode();
        const inserted = await client.query(
          `INSERT INTO activation_codes
             (code, name, email, stripe_session, purchase_type,
              payment_intent_id, payment_status, paid_at, redeemed, created_at)
           VALUES ($1, $2, $3, $4, 'consumer_activation', $5, 'paid', $6, false, NOW())
           ON CONFLICT DO NOTHING
           RETURNING id, code`,
          [code, name, email, session.id, paymentIntentId, paidAt]
        );

        if (inserted.rows.length) {
          console.log("Activation created", {
            activationId: inserted.rows[0].id,
            sessionId: session.id
          });
          break;
        }

        const existing = await client.query(
          `SELECT id FROM activation_codes WHERE stripe_session = $1 LIMIT 1`,
          [session.id]
        );

        if (existing.rows.length) {
          console.log("Duplicate webhook ignored:", session.id);
          break;
        }

        if (attempt === 4) {
          throw new Error("Could not generate a unique activation code");
        }
      }
    } finally {
      client.release();
    }
  } catch (err) {
    console.error("Activation fulfillment failed:", err);
    return {
      statusCode: 500,
      body: JSON.stringify({ received: false })
    };
  }

  return {
    statusCode: 200,
    body: JSON.stringify({ received: true })
  };

};
