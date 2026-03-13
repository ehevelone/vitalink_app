const Stripe = require("stripe");
const { Pool } = require("pg");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

exports.handler = async (event) => {

  const sig = event.headers["stripe-signature"];

  let stripeEvent;

  try {

    stripeEvent = stripe.webhooks.constructEvent(
      event.body,
      sig,
      process.env.STRIPE_BILLING_WEBHOOK_SECRET
    );

    console.log("Stripe billing event:", stripeEvent.type);

  } catch (err) {

    console.error("Webhook verification failed:", err);

    return {
      statusCode: 400,
      body: `Webhook Error: ${err.message}`,
    };

  }

  const client = await pool.connect();

  try {

    if (
      stripeEvent.type === "checkout.session.completed" ||
      stripeEvent.type === "checkout.session.async_payment_succeeded"
    ) {

      const session = stripeEvent.data.object;

      const email = session.customer_details?.email || null;

      console.log("RSM signup payment:", email);

      if (email) {

        await client.query(
          `UPDATE rsms
           SET billing_active = true
           WHERE email = $1`,
          [email]
        );

        console.log("Billing activated for:", email);

      }

    }

    if (stripeEvent.type === "invoice.paid") {

      const invoice = stripeEvent.data.object;

      const email = invoice.customer_email || null;

      console.log("Subscription payment received:", email);

      if (email) {

        await client.query(
          `UPDATE rsms
           SET billing_active = true
           WHERE email = $1`,
          [email]
        );

        console.log("Billing confirmed for:", email);

      }

    }

  } catch (err) {

    console.error("Database error:", err);

  } finally {

    client.release();

  }

  return {
    statusCode: 200,
    body: JSON.stringify({ received: true })
  };

};