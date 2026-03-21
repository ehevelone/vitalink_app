const Stripe = require("stripe");
const { Pool } = require("pg");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

function generateCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

  const part = (len) =>
    Array.from({ length: len }, () =>
      chars[Math.floor(Math.random() * chars.length)]
    ).join("");

  return `VL-${part(4)}-${part(4)}`;
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

  // 🔥 HANDLE ALL SUCCESS PATHS (CARD + ACH)
  if (
    stripeEvent.type === "checkout.session.completed" ||
    stripeEvent.type === "checkout.session.async_payment_succeeded" ||
    stripeEvent.type === "invoice.paid" // ✅ ADDED FOR ACH SAFETY
  ) {

    console.log("Payment event detected");

    const obj = stripeEvent.data.object;

    // 🔥 HANDLE DIFFERENT EVENT TYPES
    let sessionId = null;
    let email = null;

    if (stripeEvent.type === "invoice.paid") {
      // ACH final settlement
      sessionId = obj.subscription || obj.id;
      email = obj.customer_email || null;

      console.log("Invoice paid (ACH cleared)");
    } else {
      // Checkout session
      sessionId = obj.id;
      email = obj.customer_details?.email || null;
    }

    console.log("Session/Ref ID:", sessionId);
    console.log("Customer email:", email);

    const code = generateCode();

    console.log("Generated code:", code);

    const client = await pool.connect();

    try {

      const existing = await client.query(
        `SELECT id FROM activation_codes
         WHERE stripe_session = $1
         LIMIT 1`,
        [sessionId]
      );

      if (existing.rows.length === 0) {

        console.log("Creating activation code row");

        await client.query(
          `INSERT INTO activation_codes
           (code, email, stripe_session, created_at)
           VALUES ($1,$2,$3,NOW())`,
          [code, email, sessionId]
        );

        console.log("Activation created:", code, email);

      } else {

        console.log("Duplicate webhook ignored:", sessionId);

      }

    } catch (err) {

      console.error("DB error:", err);

    } finally {

      client.release();

    }

  } else {

    console.log("Unhandled Stripe event:", stripeEvent.type);

  }

  return {
    statusCode: 200,
    body: JSON.stringify({ received: true })
  };

};