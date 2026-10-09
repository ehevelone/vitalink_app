const Stripe = require("stripe");
const { Pool } = require("pg");
const crypto = require("crypto");
const { getActivationPriceId } = require("./services/stripe-prices");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

function generateCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

  const part = (len) =>
    Array.from({ length: len }, () =>
      chars[crypto.randomInt(chars.length)]
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

  const paidCheckoutEvent =
    stripeEvent.type === "checkout.session.completed" ||
    stripeEvent.type === "checkout.session.async_payment_succeeded";

  if (paidCheckoutEvent) {

    console.log("Payment event detected");

    const eventSession = stripeEvent.data.object;
    const session = await stripe.checkout.sessions.retrieve(eventSession.id, {
      expand: ["line_items.data.price"],
    });
    const activationPriceId = getActivationPriceId();
    const lineItems = session.line_items?.data || [];
    const validActivationPurchase =
      session.mode === "payment" &&
      session.payment_status === "paid" &&
      lineItems.length === 1 &&
      lineItems[0].price?.id === activationPriceId &&
      lineItems[0].quantity === 1;

    if (!validActivationPurchase) {
      console.log("Checkout ignored: not a paid VitaLink activation purchase");
      return {
        statusCode: 200,
        body: JSON.stringify({ received: true, activation_created: false }),
      };
    }

    const sessionId = session.id;
    const email = session.customer_details?.email?.trim().toLowerCase() || null;

    const code = generateCode();

    const client = await pool.connect();

    try {

      await client.query("BEGIN");
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtext($1))",
        [sessionId]
      );

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

        console.log("Activation record created");

      } else {

        console.log("Duplicate webhook ignored");

      }

      await client.query("COMMIT");

    } catch (err) {

      console.error("DB error:", err);

      try {
        await client.query("ROLLBACK");
      } catch (_) {}

      return {
        statusCode: 500,
        body: JSON.stringify({ received: false, error: "Activation could not be saved" }),
      };

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
