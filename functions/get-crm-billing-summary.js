const Stripe = require("stripe");
const db = require("./services/db");
const { verifyAgentSession } = require("./services/agent-auth");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const SITE = "https://myvitalink.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type, x-agent-session",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json"
};

function reply(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify(body)
  };
}

async function ensureCrmBillingColumns() {
  await db.query(`
    ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS crm_subscription_status TEXT,
    ADD COLUMN IF NOT EXISTS crm_subscription_valid BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS crm_stripe_customer_id TEXT,
    ADD COLUMN IF NOT EXISTS crm_stripe_subscription_id TEXT
  `);
}

function prettyStatus(status) {
  const value = String(status || "inactive").replace(/_/g, " ");
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function formatDate(timestamp) {
  if (!timestamp) {
    return null;
  }

  return new Date(timestamp * 1000).toLocaleDateString("en-US", {
    year: "numeric",
    month: "long",
    day: "numeric"
  });
}

function paymentMethodLabel(paymentMethod) {
  if (!paymentMethod) {
    return "No payment method on file";
  }

  if (paymentMethod.type === "us_bank_account") {
    const bankName =
      paymentMethod.us_bank_account?.bank_name || "Bank";

    return `${bankName} account`;
  }

  if (paymentMethod.type === "card") {
    const brand =
      paymentMethod.card?.display_brand ||
      paymentMethod.card?.brand;

    return brand
      ? `${brand.charAt(0).toUpperCase()}${brand.slice(1)} card`
      : "Card on file";
  }

  return "Payment method on file";
}

function billingOwnerLabel(agent) {
  if (!agent.crm_stripe_subscription_id) {
    return "Not assigned";
  }

  if (!String(agent.crm_stripe_subscription_id).startsWith("sub_")) {
    return "Manual admin access";
  }

  if (agent.billing_owner === "agency") {
    return "Agency";
  }

  return "Agent";
}

function paymentStatusLabel(subscription) {
  const invoice = subscription?.latest_invoice;

  if (typeof invoice === "object" && invoice?.status) {
    return prettyStatus(invoice.status);
  }

  if (subscription?.status) {
    return prettyStatus(subscription.status);
  }

  return "Not available";
}

async function getPlanName(subscription) {
  const price =
    subscription?.items?.data?.[0]?.price;

  if (!price) {
    return "CRM Access";
  }

  if (price.nickname) {
    return price.nickname;
  }

  if (typeof price.product === "object" && price.product?.name) {
    return price.product.name;
  }

  if (typeof price.product === "string") {
    try {
      const product =
        await stripe.products.retrieve(price.product);

      if (product?.name) {
        return product.name;
      }
    } catch (err) {
      console.warn("Unable to retrieve Stripe product:", err.message);
    }
  }

  return "CRM Access";
}

async function getDefaultPaymentMethod(subscription, customerId) {
  if (typeof subscription.default_payment_method === "object") {
    return subscription.default_payment_method;
  }

  if (typeof subscription.default_payment_method === "string") {
    return stripe.paymentMethods.retrieve(
      subscription.default_payment_method
    );
  }

  const customer =
    await stripe.customers.retrieve(customerId);

  const invoicePaymentMethod =
    customer?.invoice_settings?.default_payment_method;

  if (typeof invoicePaymentMethod === "object") {
    return invoicePaymentMethod;
  }

  if (typeof invoicePaymentMethod === "string") {
    return stripe.paymentMethods.retrieve(invoicePaymentMethod);
  }

  return null;
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  let body = {};

  try {
    body = JSON.parse(event.body || "{}");
  } catch {
    return reply(400, { success: false, error: "Invalid request body" });
  }

  const token =
    event.headers["x-agent-session"] ||
    body.agentSessionToken;

  const sessionAgent = await verifyAgentSession({
    agentId: body.agentId,
    token
  });

  if (!sessionAgent) {
    return reply(403, { success: false, error: "Unauthorized" });
  }

  try {
    await ensureCrmBillingColumns();

    const agentRes = await db.query(
      `
      SELECT
        id,
        crm_subscription_status,
        crm_subscription_valid,
        crm_stripe_customer_id,
        crm_stripe_subscription_id,
        billing_owner
      FROM agents
      WHERE id = $1
      LIMIT 1
      `,
      [sessionAgent.id]
    );

    if (!agentRes.rows.length) {
      return reply(404, { success: false, error: "Agent not found" });
    }

    const agent = agentRes.rows[0];

    if (!agent.crm_stripe_subscription_id) {
      return reply(200, {
        success: true,
        billing: {
          status: prettyStatus(agent.crm_subscription_status),
          plan: "CRM Access",
          payment_method: "No payment method on file",
          next_billing_date: null,
          billing_owner: billingOwnerLabel(agent),
          last_payment_status: "Not available",
          active: false
        }
      });
    }

    if (!String(agent.crm_stripe_subscription_id).startsWith("sub_")) {
      return reply(200, {
        success: true,
        billing: {
          status: prettyStatus(agent.crm_subscription_status || "active"),
          plan: "VitaLink CRM Access",
          payment_method: "Manual admin access",
          next_billing_date: null,
          billing_owner: billingOwnerLabel(agent),
          last_payment_status: "Manual admin access",
          active: agent.crm_subscription_valid === true
        }
      });
    }

    const subscription =
      await stripe.subscriptions.retrieve(
        agent.crm_stripe_subscription_id,
        {
          expand: [
            "default_payment_method",
            "latest_invoice",
            "items.data.price.product"
          ]
        }
      );

    const paymentMethod =
      await getDefaultPaymentMethod(
        subscription,
        agent.crm_stripe_customer_id
      );

    return reply(200, {
      success: true,
      billing: {
        status: prettyStatus(subscription.status),
        plan: await getPlanName(subscription),
        payment_method: paymentMethodLabel(paymentMethod),
        next_billing_date: formatDate(subscription.current_period_end),
        billing_owner: billingOwnerLabel(agent),
        last_payment_status: paymentStatusLabel(subscription),
        active: ["active", "trialing"].includes(subscription.status)
      }
    });

  } catch (err) {
    console.error("get-crm-billing-summary error:", err);

    return reply(500, {
      success: false,
      error: "Unable to load billing summary"
    });
  }
};
