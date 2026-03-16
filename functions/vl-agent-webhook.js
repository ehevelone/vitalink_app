const Stripe = require("stripe");
const db = require("./services/db");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

// VitaLink Agent Webhook – activation code fix

function generateCode() {
  return Math.random()
    .toString(36)
    .substring(2, 8)
    .toUpperCase();
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
      process.env.STRIPE_WEBHOOK_SECRET_AGENT
    );

  } catch (err) {

    console.error("Webhook signature failed", err);

    return {
      statusCode: 400,
      body: "Webhook Error"
    };

  }

  const data = stripeEvent.data.object;

  try {

    switch (stripeEvent.type) {

      /* AGENT CREATED AFTER CHECKOUT */

      case "checkout.session.completed":

        const email = data.customer_details?.email;
        const customerId = data.customer;
        const subscriptionId = data.subscription;

        const code = generateCode();

        await db.query(
          `
          INSERT INTO agents
          (email, role, active, created_at, unlock_code, stripe_customer_id, stripe_subscription_id, subscription_status)
          VALUES ($1,'agent',true,NOW(),$2,$3,$4,'active')
          ON CONFLICT (email)
          DO UPDATE SET
            stripe_customer_id = EXCLUDED.stripe_customer_id,
            stripe_subscription_id = EXCLUDED.stripe_subscription_id,
            unlock_code = EXCLUDED.unlock_code
          `,
          [
            email,
            code,
            customerId,
            subscriptionId
          ]
        );

        console.log("Agent created:", email, code);

      break;


      /* NEW AGENT SUBSCRIPTION */

      case "customer.subscription.created":

        await db.query(
          `
          UPDATE agents
          SET
            stripe_subscription_id = $1,
            subscription_status = 'active'
          WHERE stripe_customer_id = $2
          `,
          [
            data.id,
            data.customer
          ]
        );

      break;


      /* SUBSCRIPTION UPDATED */

      case "customer.subscription.updated":

        await db.query(
          `
          UPDATE agents
          SET
            subscription_status = $1
          WHERE stripe_subscription_id = $2
          `,
          [
            data.status,
            data.id
          ]
        );

      break;


      /* SUBSCRIPTION CANCELED */

      case "customer.subscription.deleted":

        await db.query(
          `
          UPDATE agents
          SET
            subscription_status = 'canceled'
          WHERE stripe_subscription_id = $1
          `,
          [
            data.id
          ]
        );

      break;


      /* PAYMENT FAILED */

      case "invoice.payment_failed":

        await db.query(
          `
          UPDATE agents
          SET
            subscription_status = 'past_due'
          WHERE stripe_customer_id = $1
          `,
          [
            data.customer
          ]
        );

      break;


      /* PAYMENT SUCCESS */

      case "invoice.paid":

        await db.query(
          `
          UPDATE agents
          SET
            subscription_status = 'active'
          WHERE stripe_customer_id = $1
          `,
          [
            data.customer
          ]
        );

      break;

    }

    return {
      statusCode: 200,
      body: "Webhook received"
    };

  } catch (err) {

    console.error("Agent webhook error:", err);

    return {
      statusCode: 500,
      body: "Server error"
    };

  }

};