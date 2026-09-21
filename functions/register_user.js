// functions/register_user.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");
const crypto = require("crypto");
const Stripe = require("stripe");
const { getActivationPriceId } = require("./services/stripe-prices");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
const ACTIVATION_AMOUNT_CENTS = 4995;

class RegistrationError extends Error {}

function reply(success, obj = {}) {
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success, ...obj }),
  };
}

function normalizeUsPhone(value) {
  let digits = String(value || "").replace(/\D/g, "");

  if (digits.length === 11 && digits.startsWith("1")) {
    digits = digits.slice(1);
  }

  if (digits.length === 10) {
    return `+1${digits}`;
  }

  return value || null;
}

function normalizeCode(value) {
  return String(value || "")
    .replace(/[\u2010-\u2015\u2212]/g, "-")
    .replace(/[^A-Za-z0-9-]/g, "")
    .trim()
    .toUpperCase();
}

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function getEmailValidationError(value) {
  const email = normalizeEmail(value);
  if (!email) return "Email required";

  const emailPattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$/;
  if (!emailPattern.test(email) || email.includes("..") || email.startsWith(".") || email.endsWith(".")) {
    return "Enter a valid email";
  }

  const tld = email.split(".").pop();
  const commonTypos = new Set(["coim", "comm", "conm", "cmo", "ocm", "cpm", "gom"]);
  if (commonTypos.has(tld)) {
    return "Check the email ending. Did you mean .com?";
  }

  return null;
}

async function ensureUserSessionColumns() {
  await db.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ
  `);
}

async function createUserSession(executor, userId) {
  const token = crypto.randomBytes(32).toString("hex");
  const expires = new Date(Date.now() + 180 * 24 * 60 * 60 * 1000);

  await executor.query(
    `
    UPDATE users
    SET session_token = $1,
        session_expires = $2
    WHERE id = $3
    `,
    [token, expires, userId]
  );

  return token;
}

function getPaymentIntentId(value) {
  if (!value) return null;
  return typeof value === "string" ? value : value.id;
}

async function verifyLegacyStripeActivation(row) {
  if (!row.stripe_session || !row.stripe_session.startsWith("cs_")) {
    throw new RegistrationError("This purchase code needs manual review");
  }

  const session = await stripe.checkout.sessions.retrieve(row.stripe_session, {
    expand: ["line_items.data.price"]
  });
  const lineItems = session.line_items?.data || [];
  const validLineItem = lineItems.length === 1 &&
    lineItems[0].price?.id === getActivationPriceId() &&
    lineItems[0].quantity === 1;

  if (
    session.mode !== "payment" ||
    session.payment_status !== "paid" ||
    session.currency !== "usd" ||
    session.amount_total !== ACTIVATION_AMOUNT_CENTS ||
    !validLineItem
  ) {
    throw new RegistrationError("This purchase could not be verified as paid");
  }

  const email = normalizeEmail(
    session.customer_details?.email || session.customer_email
  );
  if (!email) {
    throw new RegistrationError("This purchase is missing a verified email address");
  }

  return {
    name: session.customer_details?.individual_name ||
      session.customer_details?.name || row.name || null,
    email,
    paymentIntentId: getPaymentIntentId(session.payment_intent),
    paidAt: new Date(session.created * 1000)
  };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
  return {
    statusCode: 200,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: "",
  };
}

if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        body: JSON.stringify({ error: "Method Not Allowed" }),
      };
    }

    const body = JSON.parse(event.body || "{}");
    const { firstName, lastName, phone, password, platform } = body;
    const email = normalizeEmail(body.email);
    const promoCode = normalizeCode(body.promoCode);

    await ensureUserSessionColumns();

    if (!firstName || !lastName || !email || !password || !promoCode) {
      return reply(false, { error: "Missing required fields" });
    }

    const emailError = getEmailValidationError(email);
    if (emailError) {
      return reply(false, { error: emailError });
    }

    // ✅ Hash password
    const password_hash = await bcrypt.hash(password, 10);

    const client = await db.connect();
    let user;
    let sessionToken;

    try {
      await client.query("BEGIN");

      let agentId = null;
      let purchaseCode = null;
      let activationId = null;

      // Agent codes keep their existing precedence and behavior.
      const agentResult = await client.query(
        `SELECT id, active FROM agents WHERE unlock_code = $1 LIMIT 1`,
        [promoCode]
      );

      if (agentResult.rows.length) {
        const agent = agentResult.rows[0];
        if (!agent.active) {
          throw new RegistrationError("Agent subscription inactive");
        }
        agentId = agent.id;
      } else {
        const activationResult = await client.query(
          `SELECT id, code, name, email, stripe_session, purchase_type,
                  payment_status, redeemed
           FROM activation_codes
           WHERE code = $1
           LIMIT 1
           FOR UPDATE`,
          [promoCode]
        );

        if (!activationResult.rows.length) {
          throw new RegistrationError("Invalid agent or purchase activation code");
        }

        const activation = activationResult.rows[0];
        if (activation.redeemed) {
          throw new RegistrationError("Purchase activation code already used");
        }

        if (
          activation.purchase_type !== "consumer_activation" ||
          activation.payment_status !== "paid"
        ) {
          const verified = await verifyLegacyStripeActivation(activation);
          await client.query(
            `UPDATE activation_codes
             SET name = $1,
                 email = $2,
                 purchase_type = 'consumer_activation',
                 payment_intent_id = $3,
                 payment_status = 'paid',
                 paid_at = $4
             WHERE id = $5`,
            [
              verified.name,
              verified.email,
              verified.paymentIntentId,
              verified.paidAt,
              activation.id
            ]
          );
          activation.email = verified.email;
          activation.purchase_type = "consumer_activation";
          activation.payment_status = "paid";
        }

        if (normalizeEmail(activation.email) !== email) {
          throw new RegistrationError(
            "Registration email must match the email used for purchase"
          );
        }

        activationId = activation.id;
        purchaseCode = activation.code;
      }

      const result = await client.query(
        `INSERT INTO users (first_name, last_name, email, phone, password_hash, agent_id, purchase_code)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id, email, first_name, last_name, agent_id, purchase_code`,
        [
          firstName,
          lastName,
          email,
          normalizeUsPhone(phone),
          password_hash,
          agentId,
          purchaseCode,
        ]
      );

      user = result.rows[0];
      sessionToken = await createUserSession(client, user.id);

      await client.query(
        `INSERT INTO user_devices (user_id, platform, created_at, updated_at)
         VALUES ($1, $2, NOW(), NOW())
         ON CONFLICT ON CONSTRAINT user_devices_user_id_unique
         DO UPDATE SET platform = EXCLUDED.platform, updated_at = NOW()`,
        [user.id, platform || "unknown"]
      );

      if (activationId !== null) {
        const redeemed = await client.query(
          `UPDATE activation_codes
           SET redeemed = true,
               redeemed_at = NOW(),
               redeemed_by_user_id = $1
           WHERE id = $2
             AND redeemed IS NOT TRUE
           RETURNING id`,
          [user.id, activationId]
        );

        if (!redeemed.rows.length) {
          throw new RegistrationError("Purchase activation code already used");
        }
      }

      await client.query("COMMIT");
    } catch (err) {
      await client.query("ROLLBACK");
      if (err instanceof RegistrationError) {
        return reply(false, { error: err.message });
      }
      throw err;
    } finally {
      client.release();
    }

    return reply(true, {
      message: "User registered successfully ✅",
      user: {
        ...user,
        session_token: sessionToken,
      },
    });
  } catch (err) {
    console.error("❌ register_user error:", err);
    return reply(false, { error: "Server error: " + err.message });
  }
};
