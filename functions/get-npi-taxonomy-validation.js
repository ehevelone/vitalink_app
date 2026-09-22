const { requireAdmin } = require("./_adminAuth");
const {
  getLatestValidationRun,
} = require("./services/npi-taxonomy-validation");
const {
  NPI_TAXONOMY_MAPPING_RELEASE,
  NPI_TAXONOMY_MAPPING_VERSION,
} = require("./services/npi-taxonomies");

const headers = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }
  if (event.httpMethod !== "GET") {
    return { statusCode: 405, headers, body: "Method Not Allowed" };
  }

  const auth = await requireAdmin(event);
  if (auth.error) {
    return { statusCode: 401, headers, body: JSON.stringify({ error: auth.error }) };
  }

  try {
    const latest = await getLatestValidationRun();
    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        mappingVersion: NPI_TAXONOMY_MAPPING_VERSION,
        mappingRelease: NPI_TAXONOMY_MAPPING_RELEASE,
        latest,
      }),
    };
  } catch (error) {
    console.error("get-npi-taxonomy-validation error:", error);
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({ success: false, error: "Unable to load validation status" }),
    };
  }
};
