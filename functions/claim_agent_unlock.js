// functions/claim_agent_unlock.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");
const { randomBytes } = require("crypto");

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

function rsmBillingActive(rsm) {
  return rsm.billing_active === true || isAdminOverride(
    rsm.subscription_status,
    rsm.stripe_customer_id,
    rsm.stripe_subscription_id,
    rsm.stripe_subscription_item_id
  );
}

function newAgentCode() {
  return "AGT-" + randomBytes(8).toString("hex").toUpperCase();
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

    await db.query(`ALTER TABLE agents
      ADD COLUMN IF NOT EXISTS linked_rsm_id UUID,
      ADD COLUMN IF NOT EXISTS pricing_tier TEXT DEFAULT 'founders'`);
    const hashedPassword = await bcrypt.hash(password, 10);
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [cleanEmail]);

    const existing = await client.query(
      `
      SELECT id, active, password_hash, promo_code, unlock_code,
        rsm_id, billing_owner, subscription_status, stripe_subscription_id,
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
      FOR UPDATE
      `,
      [registrationCode]
    );

    let agent = existing.rows[0];
    let rsm = null;
    if (!agent || agent.rsm_id) {
      const rsmResult = await client.query(
        `SELECT id, billing_active, billing_mode, pricing_tier, subscription_status,
                stripe_customer_id, stripe_subscription_id, stripe_subscription_item_id
         FROM rsms
         WHERE ${agent ? "id" : "invite_code"} = $1 AND role = 'rsm' AND active = TRUE
         LIMIT 1 FOR UPDATE`,
        [agent ? agent.rsm_id : registrationCode]
      );
      rsm = rsmResult.rows[0];
      if (!rsm || !rsmBillingActive(rsm)) {
        await client.query("ROLLBACK");
        return fail(rsm ? "Office billing must be active before enrolling agents." : "Invalid agent registration code", rsm ? 402 : 404);
      }
    }

    if (!agent && !rsm) {
      await client.query("ROLLBACK");
      return fail("Invalid agent registration code", 404);
    }

    if (agent?.password_hash) {
      await client.query("ROLLBACK");
      return fail("Agent registration code already used");
    }

    const duplicate = await client.query(
      `SELECT id FROM agents WHERE LOWER(email) = $1 AND id IS DISTINCT FROM $2 LIMIT 1`,
      [cleanEmail, agent?.id || null]
    );
    if (duplicate.rows.length) {
      await client.query("ROLLBACK");
      return fail("An agent account already exists with this email. Please log in or contact your RSM.", 409);
    }

    const matchingRsm = await client.query(
      `
      SELECT id
      FROM rsms
      WHERE LOWER(email) = LOWER($1)
        AND role = 'rsm'
        AND active = TRUE
      LIMIT 1
      `,
      [cleanEmail]
    );

    const selfRsmId = agent &&
      matchingRsm.rows.length > 0 &&
      (!agent.rsm_id || String(agent.rsm_id) === String(matchingRsm.rows[0].id))
        ? matchingRsm.rows[0].id
        : null;

    const promoCode =
      agent?.promo_code ||
      "AG-" + Math.random().toString(36).substring(2, 10).toUpperCase();

    const billingOwner = selfRsmId ? "rsm" : rsm ?
      (rsm.billing_mode === "agent_paid" ? "agent" : "agency") : agent.billing_owner;
    const requiresAgentBilling = billingOwner === "agent" &&
      !isAdminOverride(agent?.subscription_status) &&
      !(agent?.stripe_subscription_id && agent?.subscription_status === "active");
    const subscriptionStatus = requiresAgentBilling ? "pending_payment" :
      selfRsmId || rsm ? "active" : (agent.subscription_status || "active");
    const active = !requiresAgentBilling;
    const pricingTier = rsm?.pricing_tier === "regular" ? "regular" : "founders";

    const result = agent ? await client.query(
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
          active = $14,
          rsm_id = COALESCE(rsm_id, $13),
          linked_rsm_id = $13,
          billing_owner = $15,
          subscription_status = $16,
          pricing_tier = CASE WHEN $17::boolean THEN $18 ELSE pricing_tier END,
          promo_code = $11
      WHERE id = $12 AND password_hash IS NULL
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
        selfRsmId,
        active,
        billingOwner,
        subscriptionStatus,
        Boolean(rsm),
        pricingTier,
      ]
    ) : await client.query(
      `INSERT INTO agents
        (unlock_code, email, password_hash, npn, phone, name, agency_name,
         agency_street, agency_address, agency_city, agency_state, agency_zip,
         active, role, rsm_id, billing_owner, subscription_status, pricing_tier,
         promo_code, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $8, $9, $10, $11,
               $12, 'agent', $13, $14, $15, $16, $17, NOW())
       RETURNING id, name, email, phone, npn, agency_name, agency_street, agency_city,
         agency_state, agency_zip, promo_code, active, role, subscription_status`,
      [newAgentCode(), cleanEmail, hashedPassword, npn, normalizeUsPhone(phone),
        name, agencyName, agencyStreet, agencyCity,
        String(agencyState || "").trim().toUpperCase() || null, agencyZip,
        active, rsm.id, billingOwner, subscriptionStatus, pricingTier, promoCode]
    );

    const row = result.rows[0];
    if (!row) throw new Error("Agent registration could not be completed");
    await client.query("COMMIT");

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
      billingOwner: billingOwner || null,
      subscriptionStatus: row.subscription_status || null,
    });
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error("claim_agent_unlock error:", err);
    return fail("Server error: " + err.message, 500);
  }
};
