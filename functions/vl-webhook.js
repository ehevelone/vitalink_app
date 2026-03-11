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

  const sig = event.headers["stripe-signature"];

  let stripeEvent;

  try {

    stripeEvent = stripe.webhooks.constructEvent(
      event.body,
      sig,
      process.env.STRIPE_WEBHOOK_SECRET
    );

  } catch (err) {

    return {
      statusCode: 400,
      body: `Webhook Error: ${err.message}`,
    };

  }

  if (stripeEvent.type === "checkout.session.completed") {

    const session = stripeEvent.data.object;

    const email = session.customer_details?.email || null;

    const code = generateCode();

    const client = await pool.connect();

    try {

      const existing = await client.query(
        `SELECT id FROM activation_codes
         WHERE stripe_session = $1
         LIMIT 1`,
        [session.id]
      );

      if (existing.rows.length === 0) {

        await client.query(
          `INSERT INTO activation_codes
           (code, email, stripe_session, created_at)
           VALUES ($1,$2,$3,NOW())`,
          [code, email, session.id]
        );

        console.log("Activation created:", code, email);

      } else {

        console.log("Duplicate webhook ignored:", session.id);

      }

    } catch (err) {

      console.error("DB error:", err);

    } finally {

      client.release();

    }

  }

  return {
    statusCode: 200,
    body: JSON.stringify({ received: true })
  };

};