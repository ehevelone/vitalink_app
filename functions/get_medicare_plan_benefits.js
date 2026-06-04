const db = require("./services/db");
const { verifyUserSession } = require("./services/user-auth");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

function parseMedicarePlanId(...values) {
  const text = values
    .filter(Boolean)
    .join("\n")
    .toUpperCase();

  const match = text.match(/\b([HSR]\d{4})[-\s]?(\d{3})(?:[-\s]?(\d{1,3}))?\b/);

  if (!match) return null;

  const contract = match[1];
  const plan = match[2].padStart(3, "0");
  const segment = String(match[3] ?? "0").padStart(3, "0");

  return {
    contract,
    plan,
    segment,
    planKey: `${contract}-${plan}-${segment}`,
    display: match[3] !== undefined ?
      `${contract}-${plan}-${Number(segment)}` :
      `${contract}-${plan}`,
  };
}

function activePlanYear(now = new Date()) {
  return Number(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/Chicago",
      year: "numeric",
    }).format(now)
  );
}

function friendlyLabel(categoryCode) {
  const labels = {
    "1a": "Inpatient Hospital",
    "1b": "Inpatient Mental Health",
    "2": "Skilled Nursing Facility",
    "3-1": "Primary Care Visit",
    "3-2": "Specialist Visit",
    "4a": "Emergency Room",
    "5a": "Urgent Care",
    "5b": "Worldwide Emergency/Urgent Care",
  };

  return labels[categoryCode] || `CMS Category ${categoryCode}`;
}

function parseJson(value) {
  if (!value) return {};
  if (typeof value === "string") {
    try {
      return JSON.parse(value);
    } catch (_) {
      return {};
    }
  }
  return value;
}

function costShareRows(plan) {
  const snapshot =
    parseJson(plan.normalized_benefits_json);
  const raw =
    parseJson(plan.raw_benefits_json);

  const rows =
    snapshot.rawMedicalCostShareByCategory ||
    raw.categories ||
    [];

  return Array.isArray(rows) ? rows : [];
}

function keyCopays(plan) {
  const rows =
    costShareRows(plan);
  const wanted =
    new Set(["1a", "2", "3-1", "3-2", "4a", "5a", "5b"]);

  const selected = rows
    .filter(row => wanted.has(String(row.categoryCode)))
    .map(row => ({
      code: row.categoryCode,
      label: friendlyLabel(String(row.categoryCode)),
      value: row.costShare,
    }));

  if (selected.length) {
    return selected;
  }

  return rows
    .slice(0, 12)
    .map(row => ({
      code: row.categoryCode,
      label: friendlyLabel(String(row.categoryCode)),
      value: row.costShare,
    }))
    .filter(row => row.value);
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return reply(200, {});
  }

  if (event.httpMethod !== "POST") {
    return reply(405, {
      success: false,
      error: "Method not allowed",
    });
  }

  try {
    const body =
      JSON.parse(event.body || "{}");
    const authorized =
      await verifyUserSession(body.userId, body.sessionToken);

    if (!authorized) {
      return reply(403, {
        success: false,
        error: "Unauthorized",
      });
    }

    const parsed =
      parseMedicarePlanId(
        body.medicarePlanId,
        body.planId,
        body.cardText,
        body.policy,
        body.carrier
      );

    if (!parsed) {
      return reply(400, {
        success: false,
        error: "No Medicare plan ID found on this card.",
      });
    }

    const planYear =
      activePlanYear();

    let result =
      await db.query(
        `
        SELECT
          plan_year,
          contract_id,
          plan_id,
          segment_id,
          plan_key,
          plan_name,
          carrier_name,
          contract_legal_name,
          plan_type,
          geography,
          moop_in_network,
          moop_combined,
          moop_out_of_network,
          normalized_benefits_json,
          raw_benefits_json
        FROM cms_medicare_plan_benefits
        WHERE plan_year = $1
          AND contract_id = $2
          AND plan_id = $3
          AND segment_id = $4
        LIMIT 1
        `,
        [planYear, parsed.contract, parsed.plan, parsed.segment]
      );

    if (!result.rows.length) {
      result =
        await db.query(
          `
          SELECT
            plan_year,
            contract_id,
            plan_id,
            segment_id,
            plan_key,
            plan_name,
            carrier_name,
            contract_legal_name,
            plan_type,
            geography,
            moop_in_network,
            moop_combined,
            moop_out_of_network,
            normalized_benefits_json,
            raw_benefits_json
          FROM cms_medicare_plan_benefits
          WHERE plan_year = $1
            AND contract_id = $2
            AND plan_id = $3
          ORDER BY
            CASE WHEN segment_id = '000' THEN 0 ELSE 1 END,
            segment_id
          LIMIT 1
          `,
          [planYear, parsed.contract, parsed.plan]
        );
    }

    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: `No current-year CMS benefits found for ${parsed.display}. The CMS import may not have loaded this plan yet.`,
        plan_id: parsed.display,
        plan_year: planYear,
      });
    }

    const plan =
      result.rows[0];

    return reply(200, {
      success: true,
      plan_year: plan.plan_year,
      plan_id: parsed.display,
      plan: {
        carrier_name: plan.carrier_name,
        plan_name: plan.plan_name,
        plan_type: plan.plan_type,
        geography: plan.geography,
        moop: {
          in_network: plan.moop_in_network,
          combined: plan.moop_combined,
          out_of_network: plan.moop_out_of_network,
        },
        key_copays: keyCopays(plan),
      },
      message: "Benefits shown for the current Medicare plan year only.",
    });
  } catch (err) {
    console.error("get_medicare_plan_benefits error:", err);

    return reply(500, {
      success: false,
      error: "Server error",
      details: err.message,
    });
  }
};
