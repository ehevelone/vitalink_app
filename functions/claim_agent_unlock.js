const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const db = require("./services/db");

function ok(obj) {
  return { statusCode: 200, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ success: true, ...obj }) };
}

function fail(msg, code = 400) {
  return { statusCode: code, headers: { "Content-Type": "application/json" }, body: JSON.stringify({ success: false, error: msg }) };
}

function normalizeUsPhone(value) {
  let digits = String(value || "").replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) digits = digits.slice(1);
  return digits.length === 10 ? `+1${digits}` : value || null;
}

function normalizeCode(value) {
  return String(value || "").replace(/[\u2010-\u2015\u2212]/g, "-").replace(/[^A-Za-z0-9-]/g, "").trim().toUpperCase();
}

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function getEmailValidationError(value) {
  const email = normalizeEmail(value);
  if (!email) return "Email required";
  const pattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$/;
  if (!pattern.test(email) || email.includes("..") || email.startsWith(".") || email.endsWith(".")) return "Enter a valid email";
  const typos = new Set(["coim", "comm", "conm", "cmo", "ocm", "cpm", "gom"]);
  return typos.has(email.split(".").pop()) ? "Check the email ending. Did you mean .com?" : null;
}

function isAdminOverride(...values) {
  return values.some((value) => String(value || "").trim().toLowerCase() === "admin_override");
}

function generatePromoCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return `AG-${Array.from(crypto.randomBytes(8), (byte) => chars[byte % chars.length]).join("")}`;
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    }, body: "" };
  }
  if (event.httpMethod !== "POST") return fail("Method not allowed", 405);

  let client;
  try {
    const body = JSON.parse(event.body || "{}");
    const registrationCode = normalizeCode(body.unlockCode);
    const cleanEmail = normalizeEmail(body.email);
    if (!registrationCode || !cleanEmail || !body.password || !body.npn) {
      return fail("Agent registration code, email, password, and NPN are required.");
    }
    if (body.agreementVersion !== "2026-09-30") return fail("The current Agent Agreement must be accepted.");
    const emailError = getEmailValidationError(cleanEmail);
    if (emailError) return fail(emailError);

    await db.query(`ALTER TABLE agents
      ADD COLUMN IF NOT EXISTS agent_agreement_version TEXT,
      ADD COLUMN IF NOT EXISTS agent_agreement_accepted_at TIMESTAMPTZ,
      ADD COLUMN IF NOT EXISTS linked_rsm_id UUID,
      ADD COLUMN IF NOT EXISTS pricing_tier TEXT DEFAULT 'founders'`);
    await db.query(`CREATE TABLE IF NOT EXISTS agent_agreement_events (
      id BIGSERIAL PRIMARY KEY,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      agreement_version TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW())`);

    client = await db.connect();
    await client.query("BEGIN");

    const agentResult = await client.query(
      `SELECT id,active,password_hash,promo_code,unlock_code,rsm_id,billing_owner,
              subscription_status,stripe_subscription_id,pricing_tier
       FROM agents
       WHERE promo_code=$1 OR (unlock_code=$1 AND active=FALSE AND password_hash IS NULL)
       ORDER BY CASE WHEN promo_code=$1 THEN 0 ELSE 1 END LIMIT 1 FOR UPDATE`,
      [registrationCode]
    );
    let agent = agentResult.rows[0] || null;
    let rsm = null;

    if (agent?.password_hash) {
      await client.query("ROLLBACK");
      return fail("Agent registration code already used");
    }
    if (agent?.rsm_id) {
      const linked = await client.query(
        `SELECT id,email,active,billing_active,billing_mode,pricing_tier,subscription_status,
                stripe_customer_id,stripe_subscription_id,stripe_subscription_item_id
         FROM rsms WHERE id=$1 AND role='rsm' LIMIT 1 FOR UPDATE`,
        [agent.rsm_id]
      );
      rsm = linked.rows[0] || null;
    } else if (!agent) {
      const direct = await client.query(
        `SELECT id,email,active,billing_active,billing_mode,pricing_tier,subscription_status,
                stripe_customer_id,stripe_subscription_id,stripe_subscription_item_id
         FROM rsms WHERE invite_code=$1 AND role='rsm' AND active=TRUE LIMIT 1 FOR UPDATE`,
        [registrationCode]
      );
      rsm = direct.rows[0] || null;
    }

    if (!agent && !rsm) {
      await client.query("ROLLBACK");
      return fail("Invalid agent registration code", 404);
    }
    if (agent?.rsm_id && !rsm) {
      await client.query("ROLLBACK");
      return fail("The linked office is not available for agent enrollment.", 402);
    }
    if (rsm) {
      const override = isAdminOverride(rsm.subscription_status, rsm.stripe_customer_id, rsm.stripe_subscription_id, rsm.stripe_subscription_item_id);
      if (rsm.active !== true || (rsm.billing_active !== true && !override)) {
        await client.query("ROLLBACK");
        return fail("Office billing must be active before enrolling agents.", 402);
      }
    }

    const duplicate = await client.query(
      `SELECT id FROM agents WHERE LOWER(email)=LOWER($1) AND ($2::integer IS NULL OR id<>$2) LIMIT 1`,
      [cleanEmail, agent?.id || null]
    );
    if (duplicate.rows.length > 0) {
      await client.query("ROLLBACK");
      return fail("An agent account already exists for this email.", 409);
    }

    const matchingRsm = await client.query(
      `SELECT id FROM rsms WHERE LOWER(email)=LOWER($1) AND role='rsm' AND active=TRUE LIMIT 1`,
      [cleanEmail]
    );
    const possibleSelfRsmId = matchingRsm.rows[0]?.id || null;
    const selfRsmId = possibleSelfRsmId && (!rsm || String(rsm.id) === String(possibleSelfRsmId)) ? possibleSelfRsmId : null;
    const alreadyPaid = Boolean(
      agent &&
      agent.billing_owner === "agent" &&
      (isAdminOverride(agent.stripe_subscription_id, agent.subscription_status) ||
        (agent.subscription_status === "active" &&
          String(agent.stripe_subscription_id || "").startsWith("sub_")))
    );
    const officePaid = rsm?.billing_mode !== "agent_paid";
    const billingOwner = selfRsmId ? "rsm" : rsm ? (officePaid ? "agency" : "agent") : agent?.billing_owner || null;
    const subscriptionStatus = selfRsmId || officePaid || alreadyPaid || !rsm ? "active" : "pending_payment";
    const active = subscriptionStatus === "active";
    const pricingTier = rsm?.pricing_tier === "regular" || agent?.pricing_tier === "regular" ? "regular" : "founders";
    const promoCode = agent?.promo_code || generatePromoCode();
    const linkedRsmId = selfRsmId || rsm?.id || agent?.rsm_id || null;
    const values = [cleanEmail, await bcrypt.hash(body.password, 10), body.npn, normalizeUsPhone(body.phone),
      body.name, body.agencyName, body.agencyStreet, body.agencyCity,
      String(body.agencyState || "").trim().toUpperCase() || null, body.agencyZip, promoCode,
      active, linkedRsmId, billingOwner, subscriptionStatus, pricingTier, body.agreementVersion];

    let saved;
    if (agent) {
      saved = await client.query(
        `UPDATE agents SET email=$1,password_hash=$2,npn=$3,phone=$4,name=$5,agency_name=$6,
           agency_street=$7,agency_address=$7,agency_city=$8,agency_state=$9,agency_zip=$10,
           promo_code=$11,active=$12,rsm_id=COALESCE(rsm_id,$13),linked_rsm_id=$13,
           billing_owner=$14,subscription_status=$15,pricing_tier=$16,
           agent_agreement_version=$17,agent_agreement_accepted_at=NOW()
         WHERE id=$18 RETURNING id,name,email,phone,npn,agency_name,agency_street,agency_city,
           agency_state,agency_zip,promo_code,unlock_code,active,role,subscription_status`,
        [...values, agent.id]
      );
    } else {
      saved = await client.query(
        `INSERT INTO agents (email,password_hash,npn,phone,name,agency_name,agency_street,agency_address,
           agency_city,agency_state,agency_zip,promo_code,active,role,rsm_id,linked_rsm_id,billing_owner,
           subscription_status,pricing_tier,agent_agreement_version,agent_agreement_accepted_at,created_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$7,$8,$9,$10,$11,$12,'agent',$13,$13,$14,$15,$16,$17,NOW(),NOW())
         RETURNING id,name,email,phone,npn,agency_name,agency_street,agency_city,agency_state,agency_zip,
           promo_code,unlock_code,active,role,subscription_status`,
        values
      );
      agent = { id: saved.rows[0].id };
    }

    await client.query("INSERT INTO agent_agreement_events (agent_id,agreement_version) VALUES ($1,$2)", [agent.id, body.agreementVersion]);
    await client.query("COMMIT");
    const row = saved.rows[0];
    const requiresAgentBilling = billingOwner === "agent" && subscriptionStatus !== "active";
    return ok({ message: "Agent registration complete", agentId: row.id, promoCode: row.promo_code,
      activationCode: row.unlock_code, name: row.name, email: row.email, phone: row.phone, npn: row.npn,
      agencyName: row.agency_name, agencyStreet: row.agency_street, agencyCity: row.agency_city,
      agencyState: row.agency_state, agencyZip: row.agency_zip, active: row.active, role: row.role,
      requiresAgentBilling, billingOwner, subscriptionStatus });
  } catch (err) {
    if (client) {
      try { await client.query("ROLLBACK"); } catch (_) {}
    }
    console.error("claim_agent_unlock error:", err);
    return fail("Server error: " + err.message, 500);
  } finally {
    if (client) client.release();
  }
};
