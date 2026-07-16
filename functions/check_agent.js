// functions/check_agent.js
const db = require("./services/db");
const { hashPassword, verifyPassword } = require("./services/passwords");
const { createAgentSession } = require("./services/agent-auth");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function ok(obj) {
  return {
    statusCode: 200,
    headers,
    body: JSON.stringify({ success: true, ...obj }),
  };
}

function fail(msg, code = 400, extra = {}) {
  return {
    statusCode: code,
    headers,
    body: JSON.stringify({ success: false, error: msg, ...extra }),
  };
}

exports.handler = async (event) => {
  try {
    // ✅ PREFLIGHT
    if (event.httpMethod === "OPTIONS") {
      return { statusCode: 200, headers, body: "" };
    }

    if (event.httpMethod !== "POST") {
      return fail("Method Not Allowed", 405);
    }

    const { email, password } = JSON.parse(event.body || "{}");

    if (!email || !password) {
      return fail("Missing email or password.");
    }

    const result = await db.query(
      "SELECT * FROM agents WHERE LOWER(email) = LOWER($1)",
      [email.trim()]
    );

    if (!result.rows.length) {
      return fail("No account found with this email.");
    }

    const agent = result.rows[0];

    if (!agent.password_hash) {
      return fail("Agent account not set up correctly.");
    }

    const passwordCheck = await verifyPassword(password, agent.password_hash);
    const isMatch = passwordCheck.valid;
    if (!isMatch) {
      return fail("Invalid password");
    }

    if (passwordCheck.legacy) {
      await db.query(
        "UPDATE agents SET password_hash = $1 WHERE id = $2",
        [await hashPassword(password), agent.id]
      );
    }

    // 🔥 FINAL ACCESS CONTROL (THIS IS THE IMPORTANT PART)

    const hasValidSubscription =
      agent.billing_owner !== null &&
      agent.subscription_status === "active";

    if (agent.billing_owner === "agent" && !hasValidSubscription) {
      return fail(
        "Billing required",
        403,
        {
          requires_payment: true,
          agentId: agent.id,
          email: agent.email,
          message:
            "Activate your VitaLink Agent Access to continue.",
        }
      );
    }

    const isAllowed =
      agent.active === true || hasValidSubscription;

    if (!isAllowed) {
      return fail(
        "Access disabled",
        403,
        {
          requires_payment: true,
          message:
            "Your agency no longer covers your access. Activate your personal plan to continue.",
        }
      );
    }

    // ✅ SUCCESS
    const token = await createAgentSession(agent.id);

    return ok({
      token,
      agent: {
        id: agent.id,
        email: agent.email,
        name: agent.name,
        phone: agent.phone,
        npn: agent.npn,
        role: agent.role || "agent",
        active: agent.active,
        billing_owner: agent.billing_owner || null,
        subscription_status: agent.subscription_status || null,
      },
    });

  } catch (err) {
    console.error(err);
    return fail("Server error");
  }
};
