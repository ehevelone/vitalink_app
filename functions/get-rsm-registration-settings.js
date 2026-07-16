const { requireAdmin } = require("./_adminAuth");

const SITE = (process.env.PUBLIC_SITE_URL || "https://myvitalink.app").replace(/\/$/, "");

const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-token, x-admin-session",
  "Access-Control-Allow-Methods": "GET, OPTIONS"
};

exports.handler = async function (event) {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "GET") {
    return {
      statusCode: 405,
      headers: corsHeaders,
      body: JSON.stringify({ success: false, error: "Method Not Allowed" })
    };
  }

  const auth = await requireAdmin(event);
  if (auth.error) {
    return {
      statusCode: 401,
      headers: corsHeaders,
      body: JSON.stringify({ success: false, error: auth.error })
    };
  }

  const creationCode = process.env.RSM_CREATION_CODE || "";

  return {
    statusCode: 200,
    headers: corsHeaders,
    body: JSON.stringify({
      success: true,
      registration_url: `${SITE}/rsm-register`,
      founders_registration_url: `${SITE}/rsm-register?pricing=founders`,
      regular_registration_url: `${SITE}/rsm-register?pricing=regular`,
      creation_code: creationCode,
      configured: Boolean(creationCode)
    })
  };
};
