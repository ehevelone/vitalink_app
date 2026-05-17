const Stripe = require("stripe");
const { Pool } = require("pg");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

async function ensureBillingColumns(client) {
  await client.query(`
    ALTER TABLE rsms
    ADD COLUMN IF NOT EXISTS billing_active BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT,
    ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT,
    ADD COLUMN IF NOT EXISTS stripe_subscription_item_id TEXT,
    ADD COLUMN IF NOT EXISTS subscription_status TEXT,
    ADD COLUMN IF NOT EXISTS current_period_end TIMESTAMPTZ
  `);
}

function getPeriodEnd(subscription, fallback) {
  const periodEnd =
    subscription?.current_period_end ||
    fallback?.lines?.data?.[0]?.period?.end ||
    null;

  return periodEnd ? new Date(periodEnd * 1000) : null;
}

function getSubscriptionItemId(subscription) {
  return subscription?.items?.data?.[0]?.id || null;
}

async function findRsm(client, values = {}) {
  const filters = [];
  const params = [];

  if (values.rsmId) {
    params.push(String(values.rsmId));
    filters.push(`id::TEXT = $${params.length}`);
  }

  if (values.subscriptionId) {
    params.push(String(values.subscriptionId));
    filters.push(`stripe_subscription_id = $${params.length}`);
  }

  if (values.customerId) {
    params.push(String(values.customerId));
    filters.push(`stripe_customer_id = $${params.length}`);
  }

  if (values.email) {
    params.push(String(values.email).toLowerCase());
    filters.push(`LOWER(email) = $${params.length}`);
  }

  if (!filters.length) {
    return null;
  }

  const result = await client.query(
    `
    SELECT id, email
    FROM rsms
    WHERE ${filters.join(" OR ")}
    ORDER BY
      CASE
        WHEN id::TEXT = $1 THEN 0
        ELSE 1
      END
    LIMIT 1
    `,
    params
  );

  return result.rows[0] || null;
}

async function markRsmBillingActive(client, rsmId, data) {
  await client.query(
    `
    UPDATE rsms
    SET billing_active = true,
        stripe_customer_id = COALESCE($1, stripe_customer_id),
        stripe_subscription_id = COALESCE($2, stripe_subscription_id),
        stripe_subscription_item_id = COALESCE($3, stripe_subscription_item_id),
        subscription_status = COALESCE($4, 'active'),
        current_period_end = COALESCE($5, current_period_end)
    WHERE id = $6
    `,
    [
      data.customerId || null,
      data.subscriptionId || null,
      data.subscriptionItemId || null,
      data.status || "active",
      data.currentPeriodEnd || null,
      rsmId
    ]
  );
}

async function markRsmBillingInactive(client, rsmId, status) {
  await client.query(
    `
    UPDATE rsms
    SET billing_active = false,
        subscription_status = $1
    WHERE id = $2
    `,
    [status, rsmId]
  );

  await client.query(
    `
    UPDATE agents
    SET active = false,
        billing_owner = NULL,
        subscription_status = $1
    WHERE rsm_id = $2
    `,
    [status, rsmId]
  );
}

async function handleCheckoutCompleted(client, session) {
  if (!session.subscription) {
    return;
  }

  const subscription =
    await stripe.subscriptions.retrieve(session.subscription);

  const rsm = await findRsm(client, {
    rsmId: session.metadata?.rsm_id || session.client_reference_id,
    customerId: session.customer,
    email: session.customer_details?.email || session.customer_email
  });

  if (!rsm) {
    console.log("No RSM found for checkout session:", session.id);
    return;
  }

  await markRsmBillingActive(client, rsm.id, {
    customerId: session.customer,
    subscriptionId: subscription.id,
    subscriptionItemId: getSubscriptionItemId(subscription),
    status: subscription.status,
    currentPeriodEnd: getPeriodEnd(subscription)
  });

  console.log("RSM billing activated:", rsm.id);
}

async function handleInvoicePaid(client, invoice) {
  const subscriptionId =
    typeof invoice.subscription === "string" ? invoice.subscription : null;

  let subscription = null;

  if (subscriptionId) {
    subscription = await stripe.subscriptions.retrieve(subscriptionId);
  }

  const rsm = await findRsm(client, {
    rsmId: subscription?.metadata?.rsm_id,
    subscriptionId,
    customerId: invoice.customer,
    email: invoice.customer_email
  });

  if (!rsm) {
    console.log("No RSM found for invoice:", invoice.id);
    return;
  }

  await markRsmBillingActive(client, rsm.id, {
    customerId: invoice.customer,
    subscriptionId,
    subscriptionItemId: getSubscriptionItemId(subscription),
    status: "active",
    currentPeriodEnd: getPeriodEnd(subscription, invoice)
  });

  console.log("RSM billing renewed:", rsm.id);
}

async function handleSubscriptionUpdated(client, subscription) {
  const rsm = await findRsm(client, {
    rsmId: subscription.metadata?.rsm_id,
    subscriptionId: subscription.id,
    customerId: subscription.customer
  });

  if (!rsm) {
    console.log("No RSM found for subscription:", subscription.id);
    return;
  }

  const active =
    ["active", "trialing"].includes(subscription.status);

  if (active) {
    await markRsmBillingActive(client, rsm.id, {
      customerId: subscription.customer,
      subscriptionId: subscription.id,
      subscriptionItemId: getSubscriptionItemId(subscription),
      status: subscription.status,
      currentPeriodEnd: getPeriodEnd(subscription)
    });
  } else {
    await markRsmBillingInactive(client, rsm.id, subscription.status);
  }

  console.log("RSM subscription updated:", rsm.id, subscription.status);
}

async function handlePaymentFailed(client, invoice) {
  const subscriptionId =
    typeof invoice.subscription === "string" ? invoice.subscription : null;

  const rsm = await findRsm(client, {
    subscriptionId,
    customerId: invoice.customer,
    email: invoice.customer_email
  });

  if (!rsm) {
    console.log("No RSM found for failed invoice:", invoice.id);
    return;
  }

  await markRsmBillingInactive(client, rsm.id, "past_due");

  console.log("RSM billing past due:", rsm.id);
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
      process.env.STRIPE_BILLING_WEBHOOK_SECRET
    );
  } catch (err) {
    console.error("Billing webhook verification failed:", err.message);

    return {
      statusCode: 400,
      body: `Webhook Error: ${err.message}`
    };
  }

  const client = await pool.connect();

  try {
    await ensureBillingColumns(client);

    const data = stripeEvent.data.object;

    console.log("Stripe billing event:", stripeEvent.type);

    switch (stripeEvent.type) {
      case "checkout.session.completed":
      case "checkout.session.async_payment_succeeded":
        await handleCheckoutCompleted(client, data);
        break;

      case "invoice.paid":
        await handleInvoicePaid(client, data);
        break;

      case "invoice.payment_failed":
        await handlePaymentFailed(client, data);
        break;

      case "customer.subscription.created":
      case "customer.subscription.updated":
        await handleSubscriptionUpdated(client, data);
        break;

      case "customer.subscription.deleted":
        await handleSubscriptionUpdated(client, data);
        break;

      default:
        console.log("Unhandled billing event:", stripeEvent.type);
        break;
    }

    return {
      statusCode: 200,
      body: JSON.stringify({ received: true })
    };

  } catch (err) {
    console.error("Billing webhook error:", err);

    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        error: "Billing webhook failed"
      })
    };

  } finally {
    client.release();
  }
};
