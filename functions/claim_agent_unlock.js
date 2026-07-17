// functions/claim_agent_unlock.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");

function ok(obj) {
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success: true, ...obj }),
  };
}

function fail(msg, code = 400) {
  return {
    statusCode: code,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success: false, error: msg }),
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

function isAdminOverride(...values) {
  return values.some((value) =>
    String(value || "").trim().toLowerCase() === "admin_override"
  );
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
      return fail("Method not allowed", 405);
    }

    const {
      unlockCode,
      email,
      password,
      npn,
      phone,
      name,
      agencyName,
      agencyStreet,
      agencyCity,
      agencyState,
      agencyZip,
    } = JSON.parse(event.body || "{}");

    const registrationCode = normalizeCode(unlockCode);
    const cleanEmail = normalizeEmail(email);

    if (!registrationCode || !cleanEmail || !password || !npn) {
      return fail(
        "Agent registration code, email, password, and NPN are required."
      );
    }

    const emailError = getEmailValidationError(cleanEmail);
    if (emailError) {
      return fail(emailError);
    }

    const existing = await db.query(
      `
      SELECT id, active, password_hash, promo_code, unlock_code,
        rsm_id, billing_owner, subscription_status,
        CASE WHEN promo_code = $1 THEN 'promo' ELSE 'unlock' END AS code_match
      FROM agents
      WHERE promo_code = $1
         OR (
           unlock_code = $1
           AND active = FALSE
           AND password_hash IS NULL
         )
      ORDER BY CASE WHEN promo_code = $1 THEN 0 ELSE 1 END
      LIMIT 1
      `,
      [registrationCode]
    );

    if (existing.rows.length === 0) {
      return fail("Invalid agent registration code", 404);
    }

    const agent = existing.rows[0];

    if (agent.password_hash) {
      return fail("Agent registration code already used");
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const promoCode =
      agent.promo_code ||
      "AG-" + Math.random().toString(36).substring(2, 10).toUpperCase();

    const result = await db.query(
      `
      UPDATE agents
      SET email = $1,
          password_hash = $2,
          npn = $3,
          phone = $4,
          name = $5,
          agency_name = $6,
          agency_street = $7,
          agency_address = $7,
          agency_city = $8,
          agency_state = $9,
          agency_zip = $10,
          active = TRUE,
          subscription_status = CASE
            WHEN billing_owner = 'agent' AND subscription_status <> 'active'
              THEN 'pending_payment'
            ELSE COALESCE(subscription_status, 'active')
          END,
          promo_code = $11
      WHERE id = $12
      RETURNING id, name, email, phone, npn, agency_name, agency_street, agency_city,
        agency_state, agency_zip, promo_code, active, role, subscription_status
      `,
      [
        cleanEmail,
        hashedPassword,
        npn,
        normalizeUsPhone(phone),
        name,
        agencyName,
        agencyStreet,
        agencyCity,
        String(agencyState || "").trim().toUpperCase() || null,
        agencyZip,
        promoCode,
        agent.id,
      ]
    );

    const row = result.rows[0];
    const requiresAgentBilling =
      !isAdminOverride(agent.subscription_status) &&
      agent.rsm_id &&
      agent.billing_owner === "agent" &&
      agent.subscription_status !== "active";

    return ok({
      message: "Agent registration complete",
      agentId: row.id,
      promoCode: row.promo_code,
      name: row.name,
      email: row.email,
      phone: row.phone,
      npn: row.npn,
      agencyName: row.agency_name,
      agencyStreet: row.agency_street,
      agencyCity: row.agency_city,
      agencyState: row.agency_state,
      agencyZip: row.agency_zip,
      active: row.active,
      role: row.role,
      requiresAgentBilling,
      billingOwner: agent.billing_owner || null,
      subscriptionStatus: requiresAgentBilling ? "pending_payment" : row.subscription_status || null,
    });
  } catch (err) {
    console.error("claim_agent_unlock error:", err);
    return fail("Server error: " + err.message, 500);
  }
};
