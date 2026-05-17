const { requireAdmin } = require("./_adminAuth");
const { Pool } = require("pg");
const Stripe = require("stripe");

const stripe = process.env.STRIPE_SECRET_KEY
  ? new Stripe(process.env.STRIPE_SECRET_KEY)
  : null;

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
  "Access-Control-Allow-Methods": "GET, OPTIONS"
};

async function getStripeQuantity(subscriptionItemId) {
  if (!stripe || !subscriptionItemId || !subscriptionItemId.startsWith("si_")) {
    return null;
  }

  try {
    const item = await stripe.subscriptionItems.retrieve(subscriptionItemId);
    return Number(item.quantity || 0);
  } catch (err) {
    console.warn("admin-stats Stripe quantity lookup failed:", err.message);
    return null;
  }
}

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "GET") {
    return { statusCode: 405, headers: corsHeaders, body: "Method Not Allowed" };
  }

  const auth = await requireAdmin(event);
  if (auth.error) {
    return { statusCode: 401, headers: corsHeaders, body: auth.error };
  }

  let client;

  try {
    client = await pool.connect();

    await client.query(`
      ALTER TABLE rsms
      ADD COLUMN IF NOT EXISTS billing_active BOOLEAN DEFAULT false,
      ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT,
      ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT,
      ADD COLUMN IF NOT EXISTS stripe_subscription_item_id TEXT,
      ADD COLUMN IF NOT EXISTS subscription_status TEXT,
      ADD COLUMN IF NOT EXISTS current_period_end TIMESTAMPTZ
    `);

    // 🔥 ONE QUERY → FULL REPORT
    const stats = await client.query(`
      SELECT
        -- 1A: TOTAL RSMS
        (SELECT COUNT(*) FROM rsms WHERE role='rsm') AS total_rsms,

        -- 1B: AGENTS UNDER RSMS
        COUNT(DISTINCT a.id) FILTER (WHERE a.rsm_id IS NOT NULL) AS rsm_agents,

        -- 1C: USERS UNDER THOSE AGENTS
        COUNT(u.id) FILTER (WHERE a.rsm_id IS NOT NULL AND u.agent_id IS NOT NULL) AS rsm_users,

        -- 2A: INDEPENDENT AGENTS
        COUNT(DISTINCT a.id) FILTER (WHERE a.rsm_id IS NULL AND u.agent_id IS NOT NULL) AS independent_agents,

        -- 2B: THEIR USERS
        COUNT(u.id) FILTER (WHERE a.rsm_id IS NULL AND u.agent_id IS NOT NULL) AS independent_agent_users,

        -- 3: INDEPENDENT USERS
        COUNT(u.id) FILTER (WHERE u.agent_id IS NULL) AS independent_users

      FROM users u
      LEFT JOIN agents a ON u.agent_id = a.id
    `);

    const rsmSummary = await client.query(`
      WITH client_counts AS (
        SELECT
          agent_id,
          COUNT(*)::INT AS client_count
        FROM users
        WHERE agent_id IS NOT NULL
        GROUP BY agent_id
      )
      SELECT
        r.id,
        r.email,
        r.phone,
        r.name,
        r.region,
        r.active,
        r.billing_active,
        r.subscription_status,
        r.current_period_end,
        r.stripe_subscription_item_id,
        r.created_at,
        r.invite_code,
        COUNT(a.id)::INT AS agent_count,
        COUNT(a.id) FILTER (WHERE a.active = TRUE)::INT AS active_agent_count,
        COALESCE(SUM(cc.client_count), 0)::INT AS client_count,
        COALESCE(
          JSON_AGG(
            JSON_BUILD_OBJECT(
              'id', a.id,
              'email', a.email,
              'active', a.active,
              'billing_owner', a.billing_owner,
              'subscription_status', a.subscription_status,
              'client_count', COALESCE(cc.client_count, 0),
              'created_at', a.created_at
            )
            ORDER BY a.created_at DESC NULLS LAST
          ) FILTER (WHERE a.id IS NOT NULL),
          '[]'::json
        ) AS agents
      FROM rsms r
      LEFT JOIN agents a ON a.rsm_id = r.id
      LEFT JOIN client_counts cc ON cc.agent_id = a.id
      WHERE r.role = 'rsm'
      GROUP BY
        r.id,
        r.email,
        r.phone,
        r.name,
        r.region,
        r.active,
        r.billing_active,
        r.subscription_status,
        r.current_period_end,
        r.stripe_subscription_item_id,
        r.created_at,
        r.invite_code
      ORDER BY r.created_at DESC NULLS LAST, r.email ASC
    `);

    client.release();
    client = null;

    const row = stats.rows[0];
    const rsms = await Promise.all(
      rsmSummary.rows.map(async (rsm) => {
        const billedQuantity =
          await getStripeQuantity(rsm.stripe_subscription_item_id);
        const expectedQuantity =
          rsm.billing_active === true
            ? Math.max(Number(rsm.active_agent_count || 0), 1)
            : 0;
        const auditStatus =
          billedQuantity === null
            ? "not_checked"
            : billedQuantity === expectedQuantity
              ? "matched"
              : "mismatch";

        return {
          id: rsm.id,
          email: rsm.email,
          phone: rsm.phone,
          name: rsm.name,
          region: rsm.region,
          active: rsm.active === true,
          billing_active: rsm.billing_active === true,
          subscription_status: rsm.subscription_status,
          current_period_end: rsm.current_period_end,
          created_at: rsm.created_at,
          invite_code: rsm.invite_code,
          agent_count: Number(rsm.agent_count || 0),
          active_agent_count: Number(rsm.active_agent_count || 0),
          client_count: Number(rsm.client_count || 0),
          billed_quantity: billedQuantity,
          expected_billed_quantity: expectedQuantity,
          billing_audit_status: auditStatus,
          agents: Array.isArray(rsm.agents) ? rsm.agents : []
        };
      })
    );
    const billingAudit = {
      checked: rsms.filter((rsm) => rsm.billing_audit_status !== "not_checked").length,
      matched: rsms.filter((rsm) => rsm.billing_audit_status === "matched").length,
      mismatches: rsms.filter((rsm) => rsm.billing_audit_status === "mismatch").length,
      not_checked: rsms.filter((rsm) => rsm.billing_audit_status === "not_checked").length
    };

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        total_rsms: Number(row.total_rsms),

        rsm_agents: Number(row.rsm_agents),
        rsm_users: Number(row.rsm_users),

        independent_agents: Number(row.independent_agents),
        independent_agent_users: Number(row.independent_agent_users),

        independent_users: Number(row.independent_users)
        ,
        billing_audit: billingAudit,
        rsms
      })
    };

  } catch (err) {
    console.error("admin-stats error:", err);

    if (client) client.release();

    return { statusCode: 500, headers: corsHeaders, body: "Server error" };
  }
};
