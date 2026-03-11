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

    const email = session.customer_details.email;

    const code =
      "VL-" + Math.random().toString(36).substring(2, 8).toUpperCase();

    const client = await pool.connect();

    await client.query(
      `INSERT INTO activation_codes (code, email, created_at)
       VALUES ($1,$2,NOW())`,
      [code, email]
    );

    client.release();

    console.log("Activation created:", code, email);
  }

  return {
    statusCode: 200,
    body: JSON.stringify({ received: true })
  };
};