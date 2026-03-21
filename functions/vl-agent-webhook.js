const Stripe = require("stripe");
const db = require("./services/db");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

// VitaLink Agent Webhook

function generateAgentCode() {
  return "AG-" + Math.random().toString(36).substring(2,10).toUpperCase();
}

function generateClientCode() {
  return "CL-" + Math.random().toString(36).substring(2,12).toUpperCase();
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

        const email =
          data.customer_details?.email ||
          data.customer_email ||
          "";

        const customerId = data.customer;
        const subscriptionId = data.subscription;

        // 🔥 NEW: pull metadata (from checkout)
        const agentIdFromMeta =
          data.metadata?.agentId || null;

        const agentCode = generateAgentCode();
        const clientCode = generateClientCode();

        console.log("Generated agent unlock code:", agentCode);
        console.log("Generated client referral code:", clientCode);
        console.log("Metadata agentId:", agentIdFromMeta);

        await db.query(
          `
          INSERT INTO agents
          (
            email,
            role,
            active,
            created_at,
            promo_code,
            unlock_code,
            stripe_customer_id,
            stripe_subscription_id,
            subscription_status,
            subscription_valid
          )
          VALUES
          (
            $1,
            'agent',
            true,
            NOW(),
            $2,
            $3,
            $4,
            $5,
            'active',
            true
          )
          ON CONFLICT (email)
          DO UPDATE SET
            stripe_customer_id = EXCLUDED.stripe_customer_id,
            stripe_subscription_id = EXCLUDED.stripe_subscription_id,
            promo_code = EXCLUDED.promo_code,
            unlock_code = EXCLUDED.unlock_code,
            subscription_status = 'active',
            subscription_valid = true
          `,
          [
            email,
            agentCode,
            clientCode,
            customerId,
            subscriptionId
          ]
        );

        console.log("Agent created/updated:", email);

      break;


      /* 🔥 ACH INITIAL (DO NOT ACTIVATE HERE) */

      case "checkout.session.async_payment_succeeded":

        console.log("ACH started (agent)");

      break;


      /* NEW SUBSCRIPTION */

      case "customer.subscription.created":

        await db.query(
          `
          UPDATE agents
          SET
            stripe_subscription_id = $1,
            subscription_status = 'active',
            subscription_valid = true
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
            subscription_status = $1,
            subscription_valid = $2
          WHERE stripe_subscription_id = $3
          `,
          [
            data.status,
            data.status === "active",
            data.id
          ]
        );

      break;


      /* SUBSCRIPTION CANCELLED */

      case "customer.subscription.deleted":

        await db.query(
          `
          UPDATE agents
          SET
            subscription_status = 'canceled',
            subscription_valid = false
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
            subscription_status = 'past_due',
            subscription_valid = false
          WHERE stripe_customer_id = $1
          `,
          [
            data.customer
          ]
        );

      break;


      /* 🔥 FINAL PAYMENT SUCCESS (CARD + ACH CLEARED) */

      case "invoice.paid":

        await db.query(
          `
          UPDATE agents
          SET
            subscription_status = 'active',
            subscription_valid = true
          WHERE stripe_customer_id = $1
          `,
          [
            data.customer
          ]
        );

        console.log("Agent payment confirmed:", data.customer);

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