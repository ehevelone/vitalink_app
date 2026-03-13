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

    /* CHECKOUT COMPLETED */

    if (
      stripeEvent.type === "checkout.session.completed" ||
      stripeEvent.type === "checkout.session.async_payment_succeeded"
    ) {

      const session = stripeEvent.data.object;

      const email = session.customer_details?.email || null;

      console.log("RSM signup payment:", email);

      if (email && session.subscription) {

        const subscription = await stripe.subscriptions.retrieve(
          session.subscription
        );

        const itemId = subscription.items.data[0].id;

        await client.query(
          `UPDATE rsms
           SET billing_active = true,
               stripe_customer_id = $1,
               stripe_subscription_id = $2,
               stripe_subscription_item_id = $3,
               subscription_status = $4,
               current_period_end = to_timestamp($5)
           WHERE email = $6`,
          [
            session.customer,
            subscription.id,
            itemId,
            subscription.status,
            subscription.current_period_end,
            email
          ]
        );

        console.log("RSM billing activated:", email);

      }

    }

    /* INVOICE PAID (SUBSCRIPTION RENEWAL) */

    if (stripeEvent.type === "invoice.paid") {

      const invoice = stripeEvent.data.object;

      const email = invoice.customer_email || null;

      console.log("Subscription renewal:", email);

      if (email) {

        await client.query(
          `UPDATE rsms
           SET billing_active = true,
               subscription_status = 'active',
               current_period_end = to_timestamp($1)
           WHERE email = $2`,
          [
            invoice.lines.data[0].period.end,
            email
          ]
        );

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