const { requireAdmin } = require("./_adminAuth");
const {
  markEmailSent,
  saveValidationRun,
  sendValidationEmail,
  validateTaxonomyMappings,
} = require("./services/npi-taxonomy-validation");

const headers = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }
  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers, body: "Method Not Allowed" };
  }

  const auth = await requireAdmin(event);
  if (auth.error) {
    return { statusCode: 401, headers, body: JSON.stringify({ error: auth.error }) };
  }

  try {
    const report = await validateTaxonomyMappings();
    const runId = await saveValidationRun(report, "manual");
    await sendValidationEmail(report);
    await markEmailSent(runId);
    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({ success: true, report }),
    };
  } catch (error) {
    console.error("run-npi-taxonomy-validation error:", error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({ success: false, error: "Taxonomy validation failed" }),
    };
  }
};
